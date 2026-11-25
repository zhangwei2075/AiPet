"""按 Petdex 范式生成宠物动作帧（可重复运行，只依赖 Pillow + numpy）。

动作清单（v2）
--------
idle / walk / run / hop / drop / lie / talk / eat / sleepy / angry / spin，
新增 stretch（伸懒腰/play bow）/ wag（开心摇尾）/ shake（抖毛）/
bark（汪汪叫）/ sniff（嗚探）/ celebrate（作揆庆祝）。

朝向约定
--------
项目约定「原画朝左」（Petdex 导入时统一翻转，见 petdex_importer.dart）。
侧面底图头朝右，所以**所有侧面视角动作（walk / run / 六个新动作）
合成后统一水平镜像成朝左**再落盘；`walk_left` / `run_left`
直接复用朝左的同一批文件（照片宠物只有一份侧面素材，
不存在独立绘制的第二朝向）。


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

# 纯侧面标定（exports/有财/_ai/side_profile_raw_cut.png，90° 正侧视、头朝右）。
# v2：腿部椭圆半径比初版放大约 12% —— 摆幅加大后，饱和内核必须覆盖更大的扫掠区，
# 否则白描边会在腿离原位后拖出弧形细丝（见 Rig 注释）。
# 和 SIDE 的区别：身体轴水平展开，四条腿沿 x 前后排开、上下错位（远侧稍高），
# 后腿不再被卫衣下摆挡住 —— 这是步幅能拉大的前提。坐标不能和 SIDE 互换。
# 数值由轮廓的行 / 列投影实测（y=490 行四段腿区间：38-119 / 250-341 / 349-394，
# 加 y=460 的 129-212），不要照着网格目测，正侧视的腿是斜的，目测必然偏。
PROFILE_PARTS: dict[str, tuple[float, float, float, float, float, float]] = {
    "head": (390, 142, 92, 88, 332, 236),
    "ear_left": (392, 130, 46, 52, 398, 84),
    "ear_right": (440, 112, 28, 32, 432, 90),
    "mouth": (458, 180, 30, 28, 444, 174),
    "body": (295, 305, 114, 106, 295, 325),
    "front_left": (370, 452, 34, 54, 366, 382),
    "front_right": (290, 458, 52, 58, 300, 386),
    "hind_left": (85, 452, 46, 64, 112, 384),
    "hind_right": (170, 438, 44, 60, 182, 380),
    "tail": (95, 250, 58, 72, 150, 296),
}

# Petdex 标准帧数：idle 6 / run-right 8 / run-left 8 / jump 5 / failed 8 / waiting 6 ...
# v2 新增：stretch / wag / shake / bark / sniff / celebrate；idle 6→8 帧换更慢的呼吸。
FRAME_COUNTS = {
    "idle": 8,
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
    "stretch": 8,
    "wag": 6,
    "shake": 8,
    "bark": 6,
    "sniff": 6,
    "celebrate": 8,
}
FPS = {
    "idle": 6,
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
    "stretch": 5,
    "wag": 8,
    "shake": 12,
    "bark": 7,
    "sniff": 6,
    "celebrate": 8,
}

# 这些动作合成在侧面底图上，落盘前要镜像成「原画朝左」。
PROFILE_MOTIONS = ("walk", "run", "stretch", "wag", "shake", "bark", "sniff", "celebrate")


def _smoothstep(t: float) -> float:
    t = max(0.0, min(1.0, float(t)))
    return t * t * (3.0 - 2.0 * t)


def _pulse(progress: float, start: float, duration: float) -> float:
    """一次性动作里的单峰包络：[start, start+duration] 内从 0 升到 1 再回落。"""
    t = (progress - start) / max(duration, 1e-6)
    if t < 0.0 or t > 1.0:
        return 0.0
    return math.sin(math.pi * t)

_GRID = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
_YS, _XS = _GRID[0], _GRID[1]


class Rig:
    """一套部件标定：几何定义 + 预计算的权重图与采样窗口。

    `rigid` 里的部件改用「椭圆内饱和」的权重：椭圆中心 78% 半径内权重恒为 1，
    到椭圆边界快速降到 0。肢体必须用这种，否则边界上的半权重会让原位置的肢体
    和旋转后的肢体双重曝光，叠出一道半透明的白色描边弧线（看起来像拖尾细丝）。
    """

    def __init__(
        self,
        parts: dict[str, tuple[float, float, float, float, float, float]],
        rigid: tuple[str, ...] = (),
        margin: int = 56,
    ) -> None:
        self.parts = parts
        self.weights: dict[str, np.ndarray] = {}
        self.windows: dict[str, tuple[int, int, int, int]] = {}
        for name, (cx, cy, rx, ry, px, py) in parts.items():
            r2 = ((_XS - cx) / rx) ** 2 + ((_YS - cy) / ry) ** 2
            # 采样窗口：按枢轴旋转后会偏出原区域，留足余量（rigid 分支也要有）
            self.windows[name] = (
                int(max(0, min(cx - rx, px - rx) - margin)),
                int(min(SIZE, max(cx + rx, px + rx) + margin)),
                int(max(0, min(cy - ry, py - ry) - margin)),
                int(min(SIZE, max(cy + ry, py + ry) + margin)),
            )
            if name in rigid:
                t = np.clip((1.0 - r2) / 0.22, 0.0, 1.0)
                self.weights[name] = (t * t * (3.0 - 2.0 * t)).astype(np.float32)
                continue

            # 超高斯：部件内部接近刚性、边界平滑过渡。
            # 指数取 1.5 而不是 2 —— 太硬会在旋转时把交界处撕成「幽灵肢体」。
            w = np.exp(-0.5 * np.power(r2, 1.5)).astype(np.float32)
            # 但指数 1.5 的长尾很长：椭圆外 1.5 倍半径处还有 0.17 的权重，
            # 腿一摆就会把卫衣下摆的像素按几十个百分点搬过去，叠出半透明拖影。
            # 这里做一次 smoothstep 软截断，让部件只影响自己椭圆附近。
            t = np.clip((1.6 - r2) / 0.6, 0.0, 1.0)
            self.weights[name] = (w * (t * t * (3.0 - 2.0 * t))).astype(np.float32)


# 腿和尾巴是旋转幅度最大的部件，必须用「椭圆内饱和」权重；
# 软高斯在边界上留半权重，会让原位描边和旋转后描边双重曝光，拖出白色细丝。
# v2 摆幅加大，侧面标定的采样窗口余量同步从 56 提到 76，避免旋转后的腿部采样截断。
RIG_FRONT = Rig(FRONT_PARTS)
RIG_SIDE = Rig(SIDE_PARTS, rigid=("front_left", "front_right", "hind_left", "hind_right", "tail"))
RIG_PROFILE = Rig(PROFILE_PARTS, rigid=("front_left", "front_right", "hind_left", "hind_right", "tail"), margin=76)


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
    """待机 v2：呼吸 + 尾巴摇摆 + 周期性单耳抖动 + 轻微张望。

    8 帧 @ 6fps 约 1.33s 一圈。耳朵抖动用高斯包络卡在周期 0.66 处，
    只抖左耳 —— 双耳同抖会读成「整只狗在簸」。
    """
    breath = math.sin(phase)
    u = (phase % (2 * math.pi)) / (2 * math.pi)
    twitch = math.exp(-0.5 * ((u - 0.66) / 0.055) ** 2)
    return [
        Part("body", sy=1 + 0.014 * breath, ty=-0.8 * breath),
        Part("head", ty=-2.2 * breath, tx=1.6 * math.sin(phase),
             angle=0.018 * math.sin(phase + 0.8)),
        Part("ear_left", angle=0.05 * math.sin(phase - 0.6) + 0.42 * twitch),
        Part("ear_right", angle=-0.06 * math.sin(phase - 0.6)),
        Part("tail", angle=0.30 * math.sin(phase * 2 + 0.5)),
        Part("front_left"),
        Part("front_right"),
        Part("hind_left"),
        Part("mouth", ty=-2.2 * breath,
             angle=0.018 * math.sin(phase + 0.8), sy=1.0 + 0.06 * breath),
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
    return _gait(phase, amp=0.17, lift=26.0, inward=6.0, bob=7.0, sway=8.0)


def _run(phase: float) -> list[Part]:
    parts = _gait(phase, amp=0.22, lift=36.0, inward=8.0, bob=10.0, sway=9.0)
    for part in parts:
        if part.name == "body":
            part.angle += 0.05
            part.ty -= 2.0
        elif part.name == "head":
            part.angle += 0.035
        elif part.name in ("ear_left", "ear_right"):
            part.angle *= 1.6
    return parts


def _gait_side(
    phase: float,
    table: dict[str, tuple[float, float, float, float, float, float]],
    amp: float,
    lift: float,
    bob: float,
    dim_far: float,
    phases: dict[str, float] | None = None,
    pitch: float = 0.0,
    flight: float = 0.0,
) -> list[Part]:
    """侧面视角的四足交替：腿绕肩 / 胯**前后摆动**，对角两两成对。

    正面那套「竖直抬脚 + 内收」搬到侧面会读成原地踏步 —— 侧面能看见腿的倾角，
    所以主运动只能是绕枢轴的前后摆（正角度 = 向前，底图朝右）。
    抬脚只发生在**摆动相**（腿从后往前的半个周期，即 cos > 0），支撑相脚掌贴地。
    远侧两条腿压暗并略微收窄，做出前后景深。

    `table` 传 SIDE_PARTS（3/4 视角）或 PROFILE_PARTS（纯侧面），
    两套坐标按各自底图量取，枢轴位置不同，不能混用。
    """
    def leg(name: str, ph: float, weight: float, far: bool = False) -> Part:
        cx, cy, _rx, _ry, px, py = table[name]
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

    # 步态相位表：缺省对角步态（小跑）；飞奔传 _RUN_PHASES（前对/后对各成组）。
    off = phases or {}
    # gain 拉高是必须的：腿一旦转离原位，权重不饱和的地方会留着原图同一条腿的残影，
    # 叠起来就是「一条腿变成两条」。让腿区域的权重压到 1，rest 才会归零。
    parts = [
        leg("front_left", phase + off.get("front_left", 0.0), 2.8),
        leg("hind_right", phase + off.get("hind_right", 0.0), 2.5, far=True),
        leg("front_right", phase + off.get("front_right", math.pi), 2.5, far=True),
        leg("hind_left", phase + off.get("hind_left", math.pi), 2.8),
    ]
    bounce = abs(math.sin(phase))
    head_ty = (bob * 0.85 + flight * 0.8) * bounce
    head_angle = 0.030 * math.cos(phase) + pitch * 0.6 * math.sin(phase)
    parts += [
        # 躯干：起伏 + 可选俯仰摇兒；flight 是滞空附加抬升，飞奔时身棁同步伸展。
        Part(
            "body",
            ty=-(bob + flight) * bounce,
            sx=1 - 0.018 * bounce + 0.05 * flight / 5.0 * bounce,
            angle=pitch * math.sin(phase),
        ),
        Part(
            "head",
            ty=-head_ty,
            angle=head_angle,
        ),
        Part("ear_left", angle=0.22 * math.sin(phase - 0.7) + head_angle * 0.5,
             ty=-head_ty * 0.9),
        Part("ear_right", angle=0.19 * math.sin(phase - 0.85) + head_angle * 0.5,
             ty=-head_ty * 0.9),
        Part("tail", angle=0.45 * math.sin(phase * 2)),
        # 嘴部椭圆落在头部饱和权重区内：必须继承头部的完整变换，否则两层互相拉扯出鬼影
        Part("mouth", ty=-head_ty, angle=head_angle),
    ]
    return parts


def _walk_side(phase: float, table: dict = SIDE_PARTS) -> list[Part]:
    # v2 摆幅 0.14→0.22、抬脚 16→24、起伏 4→6.5，并加躯干俯仰。
    # 腿部椭圆已扩大约 12% 且窗口余量提到 76，扫掠区仍被饱和权重覆盖。
    return _gait_side(
        phase, table=table, amp=0.22, lift=24.0, bob=6.5, dim_far=0.88, pitch=0.035
    )

# 飞奔（rotary gallop）：前腿成对、后腿成对，对内错开小相位；
# 后组领先前组约 0.75π，腾空相身体伸展并整体上抬。
_RUN_PHASES = {
    "front_left": 0.0,
    "front_right": 0.35,
    "hind_left": math.pi * 0.75,
    "hind_right": math.pi * 0.75 + 0.3,
}

def _run_side(phase: float, table: dict = SIDE_PARTS) -> list[Part]:
    parts = _gait_side(
        phase,
        table=table,
        amp=0.27,
        lift=30.0,
        bob=9.0,
        dim_far=0.86,
        phases=_RUN_PHASES,
        pitch=0.055,
        flight=5.0,
    )
    for part in parts:
        if part.name == "body":
            # 奔跑时躯干前倾、整体略微前移
            part.angle += 0.06
            part.ty -= 2.5
        elif part.name == "head":
            part.ty -= 2.0
            part.angle += 0.05
        elif part.name == "mouth":
            # 嘴跟随头部（头部下探 2px、再前倾 0.05rad）
            part.ty -= 2.0
            part.angle += 0.05
        elif part.name in ("ear_left", "ear_right"):
            # 飞奔时耳朵向后飘，甩动幅度更大
            part.angle = part.angle * 1.6 - 0.18
            part.ty -= 1.8
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
    """趴下 v2：压得更扁、头贴得更低、前爪前伸，尾巴贴地慢摆。"""
    breath = math.sin(phase)
    return [
        Part("body", ty=9.0, sy=0.90 + 0.014 * breath),
        Part("head", ty=16.0, angle=0.20, gain=1.35),
        Part("ear_left", ty=16.0, angle=0.20 + 0.10),
        Part("ear_right", ty=16.0, angle=0.20 - 0.10),
        Part("front_left", tx=-9.0, ty=3.0, angle=-0.16),
        Part("front_right", tx=9.0, ty=3.0, angle=0.16),
        Part("hind_left", ty=3.0, sy=0.94),
        Part("tail", angle=0.35 + 0.18 * math.sin(phase * 2)),
        Part("mouth", ty=16.0, angle=0.20, sy=0.94),
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
        Part("tail", angle=0.30 * nod),
    ]


def _eat(phase: float) -> list[Part]:
    """进食 v2：埋头更深（头顶接近地面）、咀嚼节奏更强、尾巴边吃边摇。"""
    dip = 0.5 + 0.5 * math.sin(phase)
    chew = math.sin(phase * 2)
    return [
        Part("head", ty=20.0 * dip, angle=0.10 * dip, gain=1.35),
        Part("mouth", ty=20.0 * dip + 2.6 * chew, angle=0.10 * dip, sy=1.0 + 0.25 * chew),
        Part("ear_left", ty=20.0 * dip, angle=0.10 * dip + 0.06 * dip),
        Part("ear_right", ty=20.0 * dip, angle=0.10 * dip - 0.06 * dip),
        Part("body", ty=2.0 * dip, sy=1 - 0.015 * dip),
        Part("tail", angle=0.30 * math.sin(phase * 2)),
        Part("front_left", ty=1.5 * dip),
        Part("front_right", ty=1.5 * dip),
        Part("hind_left"),
    ]


def _sleepy(phase: float) -> list[Part]:
    breath = math.sin(phase)
    return [
        Part("head", ty=12.0 + 1.6 * breath, angle=0.12),
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
    """生气 v2：更快的甩头跺脚、耳朵背过去、身体前倾逼近。"""
    shake = math.sin(phase * 2)
    return [
        Part("head", angle=0.07 * shake, tx=6.0 * shake),
        Part("ear_left", angle=0.42 + 0.08 * shake),
        Part("ear_right", angle=-0.42 - 0.08 * shake),
        Part("tail", angle=-0.45 * shake),
        Part("body", tx=2.5 * shake, angle=0.04),
        Part("mouth", ty=1.2, sy=1.0 + 0.2 * max(0.0, shake)),
        Part("front_left", ty=-1.5 * max(0.0, shake)),
        Part("front_right", ty=-1.5 * max(0.0, -shake)),
        Part("hind_left"),
    ]


def _stretch(progress: float) -> list[Part]:
    """伸懒腰 / play bow：胸口下沉前爪前伸、屁股撅起，停一拍再弹回来。

    包络三段：前 30% 下沉、中段保持、后 25% 收回。尾巴翘起快速小摆 ——
    这正好是狗邀请主人玩的经典姿势。
    """
    if progress < 0.30:
        d = _smoothstep(progress / 0.30)
    elif progress < 0.72:
        d = 1.0
    else:
        d = 1.0 - _smoothstep((progress - 0.72) / 0.28)
    wag = 0.16 * math.sin(progress * 2 * math.pi * 3)
    return [
        Part("head", ty=20.0 * d, tx=12.0 * d, angle=0.20 * d, gain=1.45),
        Part("mouth", ty=20.0 * d, tx=12.0 * d, angle=0.20 * d, sy=1.0 + 0.30 * d),
        Part("ear_left", ty=20.0 * d, tx=12.0 * d, angle=0.20 * d + 0.05 * d, gain=1.5),
        Part("ear_right", ty=20.0 * d, tx=12.0 * d, angle=0.20 * d - 0.05 * d, gain=1.5),
        Part("body", ty=7.0 * d, angle=0.12 * d, sy=1 - 0.05 * d, gain=1.3),
        Part("front_left", tx=-14.0 * d, ty=4.0 * d, angle=0.42 * d, gain=2.2),
        Part("front_right", tx=-10.0 * d, ty=2.0 * d, angle=0.30 * d, gain=2.2),
        Part("hind_left", ty=-2.0 * d, gain=1.6),
        Part("tail", angle=-0.30 * d + wag),
    ]

def _wag(phase: float) -> list[Part]:
    """开心摇尾：尾巴大幅扫 + 整个后躯跟着晃 + 小幅度雀跃。"""
    s = math.sin(phase * 2)
    hop_b = abs(math.sin(phase))
    return [
        Part("tail", angle=0.62 * s),
        Part("body", tx=3.5 * s, ty=-3.0 * hop_b, angle=0.030 * s),
        Part("hind_left", tx=1.5 * s),
        Part("head", ty=-2.5 * hop_b, angle=-0.035 * s),
        Part("ear_left", angle=0.16 * math.sin(phase * 2 - 0.6) - 0.018 * s),
        Part("ear_right", angle=-0.16 * math.sin(phase * 2 - 0.6) - 0.018 * s),
        Part("front_left", ty=-2.0 * hop_b),
        Part("front_right", ty=-2.0 * hop_b),
        Part("mouth", ty=-2.5 * hop_b, angle=-0.035 * s, sy=1.25 + 0.15 * s),
    ]

def _shake(phase: float) -> list[Part]:
    """抖毛 / 甩水：高频左右甩动，头和耳朵滞后半拍甩得更狠，四爪锚地。"""
    s = math.sin(phase)
    head_lag = math.sin(phase + 0.45)
    return [
        Part("body", tx=7.0 * s, angle=0.05 * s, sx=1 + 0.015 * math.sin(phase * 2)),
        Part("head", tx=9.0 * head_lag, angle=0.09 * head_lag),
        Part("mouth", tx=9.0 * head_lag, angle=0.09 * head_lag),
        Part("ear_left", angle=0.55 * math.sin(phase + 0.9)),
        Part("ear_right", angle=-0.55 * math.sin(phase + 0.7)),
        Part("tail", angle=0.32 * math.sin(phase + 1.2)),
        Part("front_left", gain=1.8),
        Part("front_right", gain=1.8),
        Part("hind_left", gain=1.8),
    ]

def _bark(progress: float) -> list[Part]:
    """汪汪叫：两声「汪」（峰在 1/4 与 3/4），张嘴昂头、胸口上挺、身体小幅后坐。"""
    e = abs(math.sin(progress * math.pi * 2)) ** 0.7
    return [
        Part("head", ty=-3.5 * e, angle=-0.10 * e, gain=1.35),
        Part("mouth", ty=-1.5 * e, angle=-0.10 * e, sy=1.0 + 0.70 * e),
        Part("ear_left", ty=-3.5 * e, angle=-0.10 * e + 0.30 * e, gain=1.5),
        Part("ear_right", ty=-3.5 * e, angle=-0.10 * e - 0.26 * e, gain=1.5),
        Part("body", tx=-3.0 * e, ty=-1.5 * e, angle=-0.035 * e),
        Part("front_left", ty=-3.0 * e),
        Part("front_right", ty=-3.0 * e),
        Part("hind_left", gain=1.5),
        Part("tail", angle=0.38 * math.sin(progress * math.pi * 8)),
    ]

def _sniff(phase: float) -> list[Part]:
    """嗅探：鼻子几乎贴地，带高频嗅闻颤动，尾巴上翘小幅快摆。"""
    tremor = 1.3 * math.sin(phase * 3)
    return [
        Part("head", ty=27.0, tx=15.0, angle=0.24, gain=1.5),
        Part("mouth", ty=27.0 + tremor, tx=15.0, angle=0.24, sy=0.92),
        Part("ear_left", ty=27.0, tx=15.0, angle=0.28, gain=1.5),
        Part("ear_right", ty=27.0, tx=15.0, angle=0.16, gain=1.5),
        Part("body", ty=2.0, angle=0.05, gain=1.25),
        Part("front_left", tx=4.0, angle=0.12, gain=1.8),
        Part("front_right", tx=4.0, angle=0.10, gain=1.8),
        Part("hind_left", gain=1.4),
        Part("tail", angle=-0.28 + 0.14 * math.sin(phase * 3)),
    ]

def _celebrate(progress: float) -> list[Part]:
    """作揖庆祝：后腿撑地坐起、前爪抱拳上下拜，用于吃到零食后的奖励。"""
    rise = math.sin(math.pi * min(1.0, progress * 1.12))
    bow = 0.5 - 0.5 * math.cos(progress * math.pi * 4)
    return [
        Part("body", ty=-6.0 * rise, angle=-0.30 * rise, gain=1.35),
        Part("head", ty=-5.0 * rise, angle=-0.10 * rise, gain=1.3),
        Part("mouth", ty=-5.0 * rise, angle=-0.10 * rise, sy=1.0 + 0.40 * rise),
        Part("ear_left", ty=-5.0 * rise, angle=-0.10 * rise - 0.06 * rise, gain=1.4),
        Part("ear_right", ty=-5.0 * rise, angle=-0.10 * rise + 0.04 * rise, gain=1.4),
        Part("front_left", ty=-26.0 * rise, tx=3.0 * rise, angle=-0.28 * rise - 0.10 * bow),
        Part("front_right", ty=-26.0 * rise, tx=3.0 * rise, angle=-0.24 * rise + 0.10 * bow),
        Part("hind_left", gain=2.0, sy=0.96),
        Part("tail", angle=-0.20 * rise + 0.35 * math.sin(progress * math.pi * 8)),
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
    # 侧面视角动作清单：走路 / 奔跑 / 六个新动作全部用纯侧面底图，
    # 合成后统一镜像成「原画朝左」（项目朝向约定，见文件头注释）。
    profiled = SRC_PROFILE is not None and key in PROFILE_MOTIONS
    side = SRC_SIDE is not None and key in ("walk", "run")
    if key == "spin":
        if SPIN_VIEWS is not None:
            return _spin_frame(yaw).round().astype(np.uint8)
        parts, flip = _spin(yaw)
        frame = compose(SRC, parts)
        return _mirror(frame) if flip else frame
    if key == "idle":
        return compose(SRC, _idle(phase))
    if profiled or side:
        table = PROFILE_PARTS if profiled else SIDE_PARTS
        rig = RIG_PROFILE if profiled else RIG_SIDE
        if key == "walk":
            frame = compose(SRC_PROFILE if profiled else SRC_SIDE,
                            _walk_side(phase, table), rig=rig)
        elif key == "run":
            frame = compose(SRC_PROFILE if profiled else SRC_SIDE,
                            _run_side(phase, table), rig=rig)
        elif key == "stretch":
            frame = compose(SRC_PROFILE, _stretch(progress), rig=rig)
        elif key == "wag":
            frame = compose(SRC_PROFILE, _wag(phase), rig=rig)
        elif key == "shake":
            frame = compose(SRC_PROFILE, _shake(phase), rig=rig)
        elif key == "bark":
            frame = compose(SRC_PROFILE, _bark(progress), rig=rig)
        elif key == "sniff":
            frame = compose(SRC_PROFILE, _sniff(phase), rig=rig)
        elif key == "celebrate":
            frame = compose(SRC_PROFILE, _celebrate(progress), rig=rig,
                            offset=(0.0, -10.0 * math.sin(math.pi * min(1.0, progress * 1.12))))
        else:
            raise KeyError(key)
        return _mirror(frame)
    return compose(SRC, _walk(phase) if key == "walk" else _run(phase))

SRC: np.ndarray = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
# 侧前 3/4 四足底图；缺省时 walk / run 退回纯侧面，再缺就退回正面标定（效果差，但不会崩）。
SRC_SIDE: np.ndarray | None = None
# 纯侧面（90°）四足底图，优先用于 walk / run。
SRC_PROFILE: np.ndarray | None = None
# 转圈用的四个视角：正面 / 坐姿侧前 / 坐姿背面 / 另一侧（侧前的水平镜像）。
# 齐了才走真实视角，缺一张就退回 `_spin` 的单图蒙皮（180° 仍是正脸）。
SPIN_VIEWS: list[np.ndarray] | None = None


def main() -> None:
    global SRC, SRC_SIDE, SRC_PROFILE, SPIN_VIEWS
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
        help="侧前 3/4 四足底图；缺省自动找 <pet-dir>/_ai/side_raw_cut.png",
    )
    parser.add_argument(
        "--profile-view",
        type=Path,
        default=None,
        help="纯侧面（90°）四足底图，优先给 walk / run 用；"
        "缺省自动找 <pet-dir>/_ai/side_profile_raw_cut.png",
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
        print(f"侧前底图：{side_path.name}（3/4 视角，纯侧面缺失时兜底）")
    else:
        print("未找到侧前底图，walk / run 退回正面标定（四条腿会叠在一起）")

    profile_path = args.profile_view or (pet_dir / "_ai" / "side_profile_raw_cut.png")
    if profile_path.exists():
        profile = Image.open(profile_path).convert("RGBA")
        if profile.size != (SIZE, SIZE):
            profile = profile.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        SRC_PROFILE = np.asarray(profile, dtype=np.float32)
        print(f"纯侧面底图：{profile_path.name}（walk / run 走正侧视标定）")

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

    # Petdex 的 run-right / run-left 是两条独立状态行。照片宠物只有一份侧面素材，
    # 朝左的 walk 帧同时就是「朝左走」的画面：walk_left / run_left 直接引用同一批
    # 文件，App 端 facing<0 时取这条序列、不再叠加运行时镜像。
    for key, mirrored in (("walk", "walk_left"), ("run", "run_left")):
        animations[mirrored] = {
            "fps": FPS[key],
            "frames": list(animations[key]["frames"]),
        }

    pack["animations"] = animations
    pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{pet_dir.name}: 生成 {written} 帧，动作 {len(FRAME_COUNTS)} 个")
    print(f"petpack.json animations: {', '.join(sorted(animations))}")


if __name__ == "__main__":
    main()
