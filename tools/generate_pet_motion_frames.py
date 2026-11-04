"""按 Petdex 范式生成宠物动作帧（可重复运行，只依赖 Pillow + numpy）。

设计要点
--------
一张正面抠图做不出 Petdex 那种逐帧手绘，但「整只宠物一起果冻变形」也不行。
这里用 **2D 分部件蒙皮（part skinning）**：

  * 身体划成若干部件（头 / 双耳 / 嘴 / 躯干 / 左右前脚 / 后脚 / 尾巴），
    每个部件有自己的**关节枢轴**与**超高斯权重**；
  * 每个部件可独立做**绕枢轴旋转 / 平移 / 缩放 / 压暗**，再按权重做 alpha 加权合成，
    没被任何部件覆盖的像素保留原图；
  * 于是四肢能绕肩/胯摆动、耳朵能滞后甩动、尾巴能摇、嘴能张合，
    而不是整张图一起缩放倾斜。

朝向
----
转圈用**绕垂直轴（Y 轴）**的分部件偏转：头保持宽度不被压扁、躯干按 |cos| 收窄、
远近侧肢体错位并压暗，过 90° 后整体镜像表示背面。全程 y 不变、没有任何 2D 旋转，
脚底始终贴地。

用法：
    python tools/generate_pet_motion_frames.py                # 默认 exports/有财
    python tools/generate_pet_motion_frames.py --pet-dir <目录>

脚本只覆盖自己管理的 animations key，不动性格 / 配色 / 其它字段。
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512

# 512×512 归一化后的部件几何：(中心 x, 中心 y, 半径 x, 半径 y, 枢轴 x, 枢轴 y)
# 两套标定，按底图视角各自量取，坐标不能互换：
#   FRONT  —— 正面坐姿（base.png），四条腿在画面上叠在一起；
#   SIDE   —— 侧前 3/4 四足站立（exports/有财/_ai/side_raw_cut.png），四条腿分开。
# 侧面多一个 hind_right（远侧后腿），正面那套没有；compose 会跳过本 rig 里不存在的部件。
FRONT_PARTS: dict[str, tuple[float, float, float, float, float, float]] = {
    "head": (250, 168, 122, 112, 250, 272),
    "ear_left": (132, 100, 44, 52, 142, 62),
    "ear_right": (382, 98, 44, 52, 374, 62),
    "mouth": (240, 210, 42, 26, 240, 190),
    "body": (276, 330, 102, 74, 276, 392),
    "front_left": (175, 424, 48, 38, 187, 386),
    "front_right": (330, 422, 52, 40, 320, 384),
    "hind_left": (246, 424, 30, 30, 246, 384),
    "tail": (415, 360, 30, 50, 402, 320),
}

# 侧面标定：近侧腿（_left）在画面右下，远侧腿（_right）偏左且被遮挡。
# 枢轴放在肩 / 胯，腿绕它前后摆动 —— 这是侧面步态的正确读法，正面那套「竖直抬脚」不适用。
SIDE_PARTS: dict[str, tuple[float, float, float, float, float, float]] = {
    "head": (372, 152, 94, 84, 330, 252),
    "ear_left": (338, 130, 42, 50, 352, 102),
    "ear_right": (414, 108, 34, 38, 394, 94),
    "mouth": (456, 176, 28, 24, 442, 166),
    "body": (256, 320, 110, 88, 256, 330),
    "front_left": (434, 424, 40, 62, 414, 350),
    "front_right": (360, 418, 36, 58, 386, 350),
    "hind_left": (240, 426, 50, 68, 246, 352),
    "hind_right": (134, 430, 44, 64, 198, 354),
    "tail": (124, 250, 48, 60, 170, 270),
}

# Petdex 标准帧数：idle 6 / run-right 8 / run-left 8 / jump 5 / failed 8 / waiting 6 ...
FRAME_COUNTS = {
    "idle": 6,
    "walk": 8,
    "run": 8,
    "hop": 5,
    "drop": 2,
    "lie": 6,
    "talk": 4,
    "eat": 6,
    "sleepy": 6,
    "angry": 8,
    "spin": 8,
}
FPS = {
    "idle": 8,
    "walk": 8,
    "run": 12,
    "hop": 10,
    "drop": 6,
    "lie": 6,
    "talk": 6,
    "eat": 8,
    "sleepy": 4,
    "angry": 10,
    "spin": 12,
}

_GRID = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
_YS, _XS = _GRID[0], _GRID[1]


class Rig:
    """一套部件标定：几何定义 + 预计算的权重图与采样窗口。"""

    def __init__(self, parts: dict[str, tuple[float, float, float, float, float, float]]) -> None:
        self.parts = parts
        self.weights: dict[str, np.ndarray] = {}
        self.windows: dict[str, tuple[int, int, int, int]] = {}
        for name, (cx, cy, rx, ry, px, py) in parts.items():
            r2 = ((_XS - cx) / rx) ** 2 + ((_YS - cy) / ry) ** 2
            # 超高斯：部件内部接近刚性、边界平滑过渡。
            # 指数取 1.5 而不是 2 —— 太硬会在旋转时把交界处撕成「幽灵肢体」。
            w = np.exp(-0.5 * np.power(r2, 1.5)).astype(np.float32)
            # 但指数 1.5 的长尾很长：椭圆外 1.5 倍半径处还有 0.17 的权重，
            # 腿一摆就会把卫衣下摆的像素按几十个百分点搬过去，叠出半透明拖影。
            # 这里做一次 smoothstep 软截断，让部件只影响自己椭圆附近。
            t = np.clip((1.6 - r2) / 0.6, 0.0, 1.0)
            self.weights[name] = (w * (t * t * (3.0 - 2.0 * t))).astype(np.float32)

            # 采样窗口：按枢轴旋转后会偏出原区域，留足余量
            margin = 56
            self.windows[name] = (
                int(max(0, min(cx - rx, px - rx) - margin)),
                int(min(SIZE, max(cx + rx, px + rx) + margin)),
                int(max(0, min(cy - ry, py - ry) - margin)),
                int(min(SIZE, max(cy + ry, py + ry) + margin)),
            )


RIG_FRONT = Rig(FRONT_PARTS)
RIG_SIDE = Rig(SIDE_PARTS)


class Part:
    """一个部件的单帧姿态：绕枢轴旋转 + 平移 + 缩放 + 压暗 + 权重增益。"""

    __slots__ = ("name", "angle", "tx", "ty", "sx", "sy", "dim", "gain")

    def __init__(
        self,
        name: str,
        angle: float = 0.0,
        tx: float = 0.0,
        ty: float = 0.0,
        sx: float = 1.0,
        sy: float = 1.0,
        dim: float = 1.0,
        gain: float = 1.0,
    ) -> None:
        self.name = name
        self.angle = angle
        self.tx = tx
        self.ty = ty
        self.sx = sx
        self.sy = sy
        self.dim = dim
        self.gain = gain


def _sample(src: np.ndarray, sx: np.ndarray, sy: np.ndarray) -> np.ndarray:
    """双线性反向采样；越界像素取透明，避免边界像素被拉成条纹。"""
    valid = (sx >= 0) & (sx < SIZE) & (sy >= 0) & (sy < SIZE)
    x0 = np.floor(sx)
    y0 = np.floor(sy)
    fx = (sx - x0)[..., None]
    fy = (sy - y0)[..., None]
    xi = np.clip(x0.astype(np.int32), 0, SIZE - 1)
    yi = np.clip(y0.astype(np.int32), 0, SIZE - 1)
    xj = np.clip(xi + 1, 0, SIZE - 1)
    yj = np.clip(yi + 1, 0, SIZE - 1)
    a = src[yi, xi]
    b = src[yi, xj]
    c = src[yj, xi]
    d = src[yj, xj]
    out = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    out[~valid] = 0.0
    return out


def _transform(src: np.ndarray, part: Part, rig: Rig) -> np.ndarray:
    """按部件姿态采样，返回**与部件窗口等大**的 RGBA 图块。"""
    _cx, _cy, _rx, _ry, px, py = rig.parts[part.name]
    x0, x1, y0, y1 = rig.windows[part.name]
    xs = _XS[y0:y1, x0:x1]
    ys = _YS[y0:y1, x0:x1]
    # 输出像素 -> 源像素：先减平移、再减缩放、最后反向旋转
    x = xs - part.tx
    y = ys - part.ty
    x = px + (x - px) / max(part.sx, 1e-3)
    y = py + (y - py) / max(part.sy, 1e-3)
    ca, sa = math.cos(part.angle), math.sin(part.angle)
    dx, dy = x - px, y - py
    return _sample(src, px + ca * dx + sa * dy, py - sa * dx + ca * dy)


def compose(
    src: np.ndarray,
    parts: list[Part],
    offset: tuple[float, float] = (0.0, 0.0),
    rig: Rig = RIG_FRONT,
) -> np.ndarray:
    """按权重合成所有部件，返回整幅 RGBA（uint8）。

    `rig` 里不存在的部件会被跳过 —— 这样同一份动作定义可以喂给正反面两套标定。
    """
    parts = [p for p in parts if p.name in rig.parts]
    total = np.zeros((SIZE, SIZE), dtype=np.float32)
    weights = []
    for part in parts:
        w = rig.weights[part.name] * part.gain
        weights.append(w)
        total += w
    scale = np.maximum(total, 1.0)

    rest = np.clip(1.0 - np.sum([w / scale for w in weights], axis=0), 0.0, 1.0)
    base = src
    if offset != (0.0, 0.0):
        base = _sample(src, _XS - offset[0], _YS - offset[1])

    acc_a = base[..., 3] * rest
    acc_rgb = base[..., :3] * acc_a[..., None]

    for part, weight in zip(parts, weights):
        x0, x1, y0, y1 = rig.windows[part.name]
        layer = _transform(src, part, rig)
        alpha = layer[..., 3] * (weight / scale)[y0:y1, x0:x1]
        acc_rgb[y0:y1, x0:x1] += layer[..., :3] * part.dim * alpha[..., None]
        acc_a[y0:y1, x0:x1] += alpha

    rgb = acc_rgb / np.maximum(acc_a, 1e-6)[..., None]
    out = np.concatenate([np.clip(rgb, 0, 255), np.clip(acc_a, 0, 255)[..., None]], axis=2)
    return out.round().astype(np.uint8)


def _mirror(arr: np.ndarray) -> np.ndarray:
    return arr[:, ::-1].copy()


def _squeeze(arr: np.ndarray, k: float) -> np.ndarray:
    """把整幅图沿水平方向绕中心压到 k 倍宽，模拟「又转过去一点」。

    纯几何压缩，不做两视角淡化 —— 淡化会让两张图各占一半 alpha，
    12fps 下读起来是双头双尾的残影；压窄轮廓反而读得出「正在侧过去」。
    """
    if abs(k - 1.0) < 1e-3:
        return arr
    cx = SIZE / 2.0
    sx = cx + (_XS - cx) / k
    return _sample(arr, sx, _YS)


# ---------------------------------------------------------------- 各动作定义


def _idle(phase: float) -> list[Part]:
    breath = math.sin(phase)
    return [
        Part("body", sy=1 + 0.012 * breath, ty=-0.6 * breath),
        Part("head", ty=-1.8 * breath, angle=0.008 * breath),
        Part("ear_left", angle=0.05 * math.sin(phase - 0.6)),
        Part("ear_right", angle=-0.05 * math.sin(phase - 0.6)),
        Part("tail", angle=0.22 * math.sin(phase * 2)),
        Part("front_left"),
        Part("front_right"),
        Part("hind_left"),
        Part("mouth"),
    ]


def _gait(phase: float, amp: float, lift: float, inward: float, bob: float, sway: float) -> list[Part]:
    """正面视角的四足交替。

    关键取舍：绕肩枢轴大角度旋转会让脚**向两侧甩**（读起来像劈叉/横移），
    所以主运动放在**竖直抬脚 + 略向身体内收 + 脚掌轻微拉伸**上，
    旋转只保留很小的胫骨倾角；身体做起伏与左右轻微重心转移，
    两个半周期靠 `sway`（2 倍频）区分开，避免 walk_0/4 长得一样。
    """
    s = math.sin(phase)
    q = math.sin(phase + math.pi)
    ls, lq = max(0.0, s), max(0.0, q)
    bounce = abs(math.sin(phase))
    sway_p = sway * math.sin(phase * 2)
    return [
        Part("front_left", angle=amp * s, ty=-lift * ls, tx=inward * ls, sy=1 + 0.08 * ls, gain=1.35),
        Part("front_right", angle=amp * q, ty=-lift * lq, tx=-inward * lq, sy=1 + 0.08 * lq, gain=1.35),
        Part("hind_left", angle=-amp * 0.7 * s, ty=-lift * 0.4 * ls, gain=1.25),
        Part("body", ty=-bob * bounce, sx=1 - 0.022 * bounce, tx=sway_p),
        Part("head", ty=-bob * 0.85 * bounce, tx=-sway_p * 0.55, angle=0.025 * math.cos(phase)),
        Part("ear_left", angle=0.16 * math.sin(phase - 0.7)),
        Part("ear_right", angle=-0.16 * math.sin(phase - 0.7)),
        Part("tail", angle=0.34 * math.sin(phase * 2)),
        Part("mouth"),
    ]


def _walk(phase: float) -> list[Part]:
    return _gait(phase, amp=0.13, lift=22.0, inward=5.0, bob=5.5, sway=6.0)


def _run(phase: float) -> list[Part]:
    parts = _gait(phase, amp=0.18, lift=32.0, inward=7.0, bob=8.0, sway=7.5)
    for part in parts:
        if part.name == "body":
            part.angle += 0.05
            part.ty -= 2.0
        elif part.name == "head":
            part.angle += 0.035
        elif part.name in ("ear_left", "ear_right"):
            part.angle *= 1.6
    return parts


def _gait_side(phase: float, amp: float, lift: float, bob: float, dim_far: float) -> list[Part]:
    """侧面视角的四足交替：腿绕肩 / 胯**前后摆动**，对角两两成对。

    正面那套「竖直抬脚 + 内收」搬到侧面会读成原地踏步 —— 侧面能看见腿的倾角，
    所以主运动只能是绕枢轴的前后摆（正角度 = 向前，底图朝右）。
    抬脚只发生在**摆动相**（腿从后往前的半个周期，即 cos > 0），支撑相脚掌贴地。
    远侧两条腿压暗并略微收窄，做出前后景深。
    """
    def leg(name: str, ph: float, weight: float, far: bool = False) -> Part:
        cx, cy, _rx, _ry, px, py = SIDE_PARTS[name]
        theta = amp * math.sin(ph)
        ca, sa = math.cos(theta), math.sin(theta)
        dx, dy = cx - px, cy - py
        # 绕枢轴转 θ，脚掌会沿圆弧**下移** (-sa·dx + (ca-1)·dy)，最大十几像素。
        # 底图的脚本来就贴着画布底边（y≈494 / 512），不补偿就会被裁成断腿，
        # 所以先把这个垂直分量反向抵消 —— 支撑相的脚底就锁在地面不动，
        # 只剩前后位移，这才是「脚不滑」的走路。
        drop = -sa * dx + (ca - 1.0) * dy
        lifting = max(0.0, math.cos(ph))
        return Part(
            name,
            angle=theta,
            ty=-drop - lift * lifting,
            sx=0.96 if far else 1.0,
            sy=1.0 + 0.07 * lifting,
            dim=dim_far if far else 1.0,
            gain=weight,
        )

    # 对角步态：近前 + 远后 同相，远前 + 近后 反相。
    # gain 拉高是必须的：腿一旦转离原位，权重不饱和的地方会留着原图同一条腿的残影，
    # 叠起来就是「一条腿变成两条」。让腿区域的权重压到 1，rest 才会归零。
    parts = [
        leg("front_left", phase, 2.6),
        leg("hind_right", phase, 2.3, far=True),
        leg("front_right", phase + math.pi, 2.3, far=True),
        leg("hind_left", phase + math.pi, 2.6),
    ]
    bounce = abs(math.sin(phase))
    parts += [
        Part("body", ty=-bob * bounce, sx=1 - 0.018 * bounce),
        Part("head", ty=-bob * 0.8 * bounce, angle=0.022 * math.cos(phase)),
        Part("ear_left", angle=0.15 * math.sin(phase - 0.7)),
        Part("ear_right", angle=0.13 * math.sin(phase - 0.8)),
        Part("tail", angle=0.30 * math.sin(phase * 2)),
        Part("mouth"),
    ]
    return parts


def _walk_side(phase: float) -> list[Part]:
    return _gait_side(phase, amp=0.27, lift=10.0, bob=4.0, dim_far=0.90)


def _run_side(phase: float) -> list[Part]:
    parts = _gait_side(phase, amp=0.36, lift=18.0, bob=6.0, dim_far=0.88)
    for part in parts:
        if part.name == "body":
            # 奔跑时躯干前倾、整体略微前移
            part.angle += 0.06
            part.ty -= 2.5
        elif part.name == "head":
            part.ty -= 2.0
            part.angle += 0.05
        elif part.name in ("ear_left", "ear_right"):
            part.angle *= 1.7
    return parts


def _hop(progress: float) -> tuple[list[Part], tuple[float, float]]:
    arc = math.sin(math.pi * progress)
    tuck = 0.5 - 0.5 * math.cos(2 * math.pi * progress)
    return (
        [
            Part("front_left", angle=0.20 * tuck, ty=-10.0 * tuck),
            Part("front_right", angle=-0.20 * tuck, ty=-10.0 * tuck),
            Part("hind_left", angle=-0.14 * tuck, ty=-6.0 * tuck),
            Part("head", ty=-2.0 * arc),
            Part("tail", angle=-0.28 * arc),
            Part("body"),
            Part("mouth"),
        ],
        (0.0, -36.0 * arc),
    )


def _drop(progress: float) -> list[Part]:
    settle = math.sin(progress * math.pi * 2) * (1 - progress)
    return [
        Part("body", sy=1 - 0.05 * settle, ty=3.5 * settle),
        Part("head", ty=2.5 * settle),
        Part("ear_left", angle=0.16 * settle),
        Part("ear_right", angle=-0.16 * settle),
        Part("front_left"),
        Part("front_right"),
        Part("hind_left"),
        Part("tail"),
        Part("mouth"),
    ]


def _lie(phase: float) -> list[Part]:
    breath = math.sin(phase)
    return [
        Part("body", ty=6.0, sy=0.94 + 0.012 * breath),
        Part("head", ty=11.0, angle=0.14),
        Part("ear_left", angle=0.24),
        Part("ear_right", angle=-0.24),
        Part("front_left", tx=-5.0, ty=2.0, angle=-0.10),
        Part("front_right", tx=5.0, ty=2.0, angle=0.10),
        Part("hind_left", ty=2.0),
        Part("tail", angle=0.30 + 0.10 * breath),
        Part("mouth", ty=10.0),
    ]


def _talk(phase: float) -> list[Part]:
    nod = math.sin(phase)
    # 嘴部张开：竖直拉伸 + 轻微下移，读起来像在说话
    open_ = 0.5 + 0.5 * math.sin(phase)
    return [
        Part("mouth", ty=1.6 + 1.8 * open_, sy=1.0 + 0.45 * open_),
        Part("head", ty=-1.2 * nod, angle=0.012 * nod),
        Part("ear_left", angle=0.07 * math.sin(phase - 0.4)),
        Part("ear_right", angle=-0.07 * math.sin(phase - 0.4)),
        Part("front_right", angle=0.16 * nod, ty=-4.0 * max(0.0, nod)),
        Part("front_left"),
        Part("hind_left"),
        Part("body"),
        Part("tail", angle=0.16 * nod),
    ]


def _eat(phase: float) -> list[Part]:
    dip = 0.5 + 0.5 * math.sin(phase)
    chew = math.sin(phase * 2)
    return [
        Part("head", ty=12.0 * dip, angle=0.06 * dip),
        Part("mouth", ty=12.0 * dip + 2.0 * chew, sy=1.15),
        Part("ear_left", angle=0.12 * dip),
        Part("ear_right", angle=-0.12 * dip),
        Part("body", ty=1.5 * dip),
        Part("tail", angle=0.26 * math.sin(phase * 2)),
        Part("front_left"),
        Part("front_right"),
        Part("hind_left"),
    ]


def _sleepy(phase: float) -> list[Part]:
    breath = math.sin(phase)
    return [
        Part("head", ty=9.0 + 1.4 * breath, angle=0.10),
        Part("ear_left", angle=0.26),
        Part("ear_right", angle=-0.26),
        Part("body", ty=4.0, sy=0.97 + 0.015 * breath),
        Part("tail", angle=0.20),
        Part("front_left", ty=1.0),
        Part("front_right", ty=1.0),
        Part("hind_left", ty=1.0),
        Part("mouth", ty=8.0),
    ]


def _angry(phase: float) -> list[Part]:
    shake = math.sin(phase * 2)
    return [
        Part("head", angle=0.05 * shake, tx=4.0 * shake),
        Part("ear_left", angle=0.30 + 0.06 * shake),
        Part("ear_right", angle=-0.30 - 0.06 * shake),
        Part("tail", angle=-0.34 * shake),
        Part("body", tx=1.5 * shake),
        Part("mouth", ty=1.2),
        Part("front_left"),
        Part("front_right"),
        Part("hind_left"),
    ]


def _spin(progress: float) -> tuple[list[Part], bool]:
    """绕垂直轴转身：头部保持可辨识，躯干按 |cos| 收窄，远近侧肢体错位并压暗。"""
    theta = 2 * math.pi * progress
    c, s = math.cos(theta), math.sin(theta)
    wide = abs(c)
    near_left = 1.0 - 0.10 * max(0.0, s)
    near_right = 1.0 - 0.10 * max(0.0, -s)
    return (
        [
            Part("body", sx=0.66 + 0.34 * wide, tx=8.0 * s, angle=0.02 * s),
            Part("head", sx=0.88 + 0.12 * wide, tx=15.0 * s, angle=0.04 * s, ty=-1.5 * abs(s)),
            Part("mouth", sx=0.88 + 0.12 * wide, tx=15.0 * s, ty=-1.5 * abs(s)),
            Part("ear_left", angle=0.18 * s, tx=6.0 * s, dim=near_left),
            Part("ear_right", angle=-0.18 * s, tx=6.0 * s, dim=near_right),
            Part("front_left", tx=-7.0 * s, dim=near_left, ty=-2.0 * abs(s)),
            Part("front_right", tx=-7.0 * s, dim=near_right, ty=-2.0 * abs(s)),
            Part("hind_left", tx=-5.0 * s, dim=near_left),
            Part("tail", tx=-14.0 * s, angle=0.22 * s),
        ],
        c < 0,  # 过 90° 后整体镜像 = 背面视角
    )


def _blend(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    """按 t 交叉淡化两张 RGBA。用预乘 alpha 混合，否则半透明边缘会发灰。"""
    w = float(np.clip(t, 0.0, 1.0))
    ta = a[..., 3:4] / 255.0
    tb = b[..., 3:4] / 255.0
    alpha = ta * (1 - w) + tb * w
    rgb = (a[..., :3] * ta) * (1 - w) + (b[..., :3] * tb) * w
    out = np.concatenate([rgb / np.maximum(alpha, 1e-6), alpha * 255.0], axis=2)
    return np.clip(out, 0.0, 255.0)


# 八格转圈的取帧表：(视角索引, 水平压窄比)。
# 视角 0=正面 / 1=坐姿侧前 / 2=坐姿背面 / 3=侧前的水平镜像（另一侧）。
# 压窄比让 45° 间隔的轮廓宽度连续：90°、270° 最窄，180° 回到背面原宽。
_SPIN_PLAN = [
    (0, 1.00),  # 0°
    (1, 1.00),  # 45°  坐姿侧前
    (1, 0.62),  # 90°  正侧面（由侧前压窄近似）
    (2, 0.92),  # 135°
    (2, 1.00),  # 180° 真背面
    (2, 0.92),  # 225°
    (3, 0.62),  # 270°
    (3, 1.00),  # 315° 另一侧斜前
]


def _spin_frame(progress: float) -> np.ndarray:
    """绕垂直轴转一圈：四个真实视角 + 中间帧柱面压窄。

    和柱面重映射的区别在于 180° 看到的是**真的背面**（后脑、耳背、连帽、
    胸背带在后背交叉、尾巴居中），而不是把正面图压窄了事。
    中间的 90°/135° 用压窄近似 —— 素材只有 45° 一格一视角，
    但压窄是个单调变化，转起来比硬切同一个视角更像在转。
    """
    assert SPIN_VIEWS is not None
    step = int(math.floor(np.clip(progress, 0.0, 0.999999) * len(_SPIN_PLAN)))
    view, k = _SPIN_PLAN[step % len(_SPIN_PLAN)]
    return _squeeze(SPIN_VIEWS[view], k).round().astype(np.uint8)


def build(key: str, index: int, count: int) -> np.ndarray:
    phase = 2 * math.pi * index / count
    progress = index / max(1, count - 1)
    # 转圈是按圆周等分的闭环：用 index/count，让 90°/270°（最窄帧）正好落在
    # 镜像切换点上，轮廓跳变被最窄宽度掩盖；用 index/(count-1) 会在 0.6 宽度处硬切。
    yaw = index / count
    # 走路 / 奔跑优先用侧面底图：正面坐姿的四条腿在画面上叠在一起，
    # 无论怎么摆都读不出「四条腿交替」，这是「只有一只脚在动」的根因。
    side = SRC_SIDE is not None and key in ("walk", "run")
    if key == "spin":
        if SPIN_VIEWS is not None:
            return _spin_frame(yaw).round().astype(np.uint8)
        parts, flip = _spin(yaw)
        frame = compose(SRC, parts)
        return _mirror(frame) if flip else frame
    if key == "idle":
        return compose(SRC, _idle(phase))
    if key == "walk":
        if side:
            return compose(SRC_SIDE, _walk_side(phase), rig=RIG_SIDE)
        return compose(SRC, _walk(phase))
    if key == "run":
        if side:
            return compose(SRC_SIDE, _run_side(phase), rig=RIG_SIDE)
        return compose(SRC, _run(phase))
    if key == "hop":
        parts, offset = _hop(progress)
        return compose(SRC, parts, offset)
    if key == "drop":
        return compose(SRC, _drop(progress))
    if key == "lie":
        return compose(SRC, _lie(phase))
    if key == "talk":
        return compose(SRC, _talk(phase))
    if key == "eat":
        return compose(SRC, _eat(phase))
    if key == "sleepy":
        return compose(SRC, _sleepy(phase))
    if key == "angry":
        return compose(SRC, _angry(phase))
    raise KeyError(key)


SRC: np.ndarray = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
# 侧面四足底图；缺省时 walk / run 退回正面标定（效果差，但不会崩）。
SRC_SIDE: np.ndarray | None = None
# 转圈用的四个视角：正面 / 坐姿侧前 / 坐姿背面 / 另一侧（侧前的水平镜像）。
# 齐了才走真实视角，缺一张就退回 `_spin` 的单图蒙皮（180° 仍是正脸）。
SPIN_VIEWS: list[np.ndarray] | None = None


def main() -> None:
    global SRC, SRC_SIDE, SPIN_VIEWS
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pet-dir",
        type=Path,
        default=ROOT / "exports" / "有财",
        help="宠物包目录（含 base.png 与 petpack.json）",
    )
    parser.add_argument(
        "--side-view",
        type=Path,
        default=None,
        help="侧面四足底图；缺省自动找 <pet-dir>/_ai/side_raw_cut.png，找不到就退回正面标定",
    )
    parser.add_argument(
        "--no-spin-views",
        action="store_true",
        help="转圈退回单图柱面重映射（180° 看不到真背面）。默认用坐姿四视角",
    )
    args = parser.parse_args()
    pet_dir: Path = args.pet_dir.resolve()
    pack_path = pet_dir / "petpack.json"
    pack = json.loads(pack_path.read_text(encoding="utf-8"))
    base_file = (pack.get("frames") or {}).get("idle", "base.png")
    base = Image.open(pet_dir / base_file).convert("RGBA")
    if base.size != (SIZE, SIZE):
        base = base.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    SRC = np.asarray(base, dtype=np.float32)

    side_path = args.side_view or (pet_dir / "_ai" / "side_raw_cut.png")
    if side_path.exists():
        side = Image.open(side_path).convert("RGBA")
        if side.size != (SIZE, SIZE):
            side = side.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        SRC_SIDE = np.asarray(side, dtype=np.float32)
        print(f"侧面底图：{side_path.name}（walk / run 走侧面标定）")
    else:
        print("未找到侧面底图，walk / run 退回正面标定（四条腿会叠在一起）")

    # 转圈的视角必须和 base.png **姿态一致**：base 是坐姿，所以这里只能用坐姿侧前 / 坐姿背面。
    # 走路用的 side_raw 是四足站姿，混进来会在转身中途从坐姿跳成站姿。
    side_sit = pet_dir / "_ai" / "side_sit_raw_cut.png"
    back_sit = pet_dir / "_ai" / "back_sit_raw_cut.png"
    if not args.no_spin_views and side_sit.exists() and back_sit.exists():
        views: list[np.ndarray] = [SRC]
        for path in (side_sit, back_sit):
            im = Image.open(path).convert("RGBA")
            if im.size != (SIZE, SIZE):
                im = im.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
            views.append(np.asarray(im, dtype=np.float32))
        views.append(np.ascontiguousarray(views[1][:, ::-1]))
        SPIN_VIEWS = views
        print(f"转圈：坐姿四视角（{side_sit.name} / {back_sit.name}）")
    else:
        print("转圈退回柱面重映射（缺坐姿侧面或背面底图）")

    animations = dict(pack.get("animations") or {})
    written = 0
    for key in FRAME_COUNTS:
        count = FRAME_COUNTS[key]
        files = []
        for index in range(count):
            frame = Image.fromarray(build(key, index, count), "RGBA")
            name = f"{key}_{index}.png"
            frame.save(pet_dir / name, optimize=True)
            files.append(name)
            written += 1
        animations[key] = {"fps": FPS[key], "frames": files}

    # Petdex 的 run-right / run-left 是两条独立状态行。这里生成**真正的水平镜像帧**，
    # 而不是把帧序列倒过来播 —— 倒序会让脚往回迈，读起来像倒带。
    for key, mirrored in (("walk", "walk_left"), ("run", "run_left")):
        left_files = []
        for index, name in enumerate(animations[key]["frames"]):
            arr = np.asarray(Image.open(pet_dir / name).convert("RGBA"), dtype=np.uint8)
            left_name = f"{key}_left_{index}.png"
            Image.fromarray(np.ascontiguousarray(arr[:, ::-1]), "RGBA").save(
                pet_dir / left_name, optimize=True
            )
            left_files.append(left_name)
            written += 1
        animations[mirrored] = {"fps": FPS[key], "frames": left_files}

    pack["animations"] = animations
    pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{pet_dir.name}: 生成 {written} 帧，动作 {len(FRAME_COUNTS)} 个")
    print(f"petpack.json animations: {', '.join(sorted(animations))}")


if __name__ == "__main__":
    main()
