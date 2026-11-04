"""按 Petdex 范式生成宠物动作帧（可重复运行，只依赖 Pillow + numpy）。

与旧版的区别
------------
旧版对**整张图**做仿射变换（缩放 / 旋转 / 平移），导致整只宠物一起"果冻化"：
走路看不出四肢交替，转圈变成绕图像中心的 2D 旋转。

Petdex 的做法是每行一个状态、每列一张**单独绘制**的帧，帧内只有局部变化
（眨眼、尾巴、四肢交替），身体基座与脚底稳定；朝向是独立序列
（run-right / run-left），不是镜像或旋转。

照片宠物只有一张正面抠图，无法凭空得到真帧，所以这里用**位移场**近似：
  * 每个身体部位（头 / 躯干 / 四只脚 / 尾巴 / 嘴）有独立的高斯权重，
    只对权重覆盖的像素施加位移，其余像素保持原样 -> 不再整图变形。
  * 脚底加了锚定衰减，走动时脚跟贴地。
  * 转圈用**绕垂直轴**的柱面重映射 + 朝向镜像，y 坐标恒定、没有任何 2D 旋转，
    生成 8 个方向帧；这是 2D 贴图的近似，真正的 8 方向仍需独立绘制/AI 生成。

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

# 针对 512×512 坐姿小狗实测的分区中心与半径（见 docs/petpack.md）。
REGIONS = {
    "head": (245, 165, 150, 130),
    "body": (256, 370, 125, 90),
    "front_left": (170, 462, 52, 46),
    "front_right": (338, 462, 52, 46),
    "hind_left": (140, 420, 34, 50),
    "hind_right": (390, 415, 34, 50),
    "tail": (402, 375, 26, 45),
    "mouth": (245, 245, 40, 26),
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

_GRID = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
_YS, _XS = _GRID[0], _GRID[1]
_ANCHOR = np.clip((496.0 - _YS) / 40.0, 0.0, 1.0)  # 越靠近脚底位移越弱


def _weight(name: str) -> np.ndarray:
    cx, cy, rx, ry = REGIONS[name]
    r2 = ((_XS - cx) / rx) ** 2 + ((_YS - cy) / ry) ** 2
    # 超高斯：中心接近 1、边缘快速衰减，让每个部位更像一块刚性部件整体移动，
    # 而不是普通高斯那样把动作摊薄成一层几乎看不出的渐变。
    return np.exp(-0.5 * r2**2)


_W = {name: _weight(name) for name in REGIONS}


def _remap(src: np.ndarray, sx: np.ndarray, sy: np.ndarray) -> Image.Image:
    """双线性反向采样：输出像素 (x,y) 取自源图 (sx,sy)。"""
    height, width = src.shape[:2]
    x0 = np.floor(sx)
    y0 = np.floor(sy)
    fx = (sx - x0)[..., None]
    fy = (sy - y0)[..., None]
    xi = np.clip(x0.astype(np.int32), 0, width - 1)
    yi = np.clip(y0.astype(np.int32), 0, height - 1)
    xj = np.clip(xi + 1, 0, width - 1)
    yj = np.clip(yi + 1, 0, height - 1)
    a = src[yi, xi].astype(np.float64)
    b = src[yi, xj].astype(np.float64)
    c = src[yj, xi].astype(np.float64)
    d = src[yj, xj].astype(np.float64)
    out = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def _field(src: np.ndarray, dx: np.ndarray, dy: np.ndarray) -> Image.Image:
    # 脚底锚定：水平位移在脚底衰减；垂直"抬脚"保留（脚离地是合理的）。
    return _remap(src, _XS - dx * _ANCHOR, _YS - dy)


def _zeros() -> tuple[np.ndarray, np.ndarray]:
    return np.zeros_like(_XS), np.zeros_like(_YS)


def _add(dx, dy, name, vx, vy, gain=1.0):
    dx += _W[name] * vx * gain
    dy += _W[name] * vy * gain


def _gait(phase: float, amplitude: float) -> tuple[np.ndarray, np.ndarray]:
    """四足交替：对角相位差 π，躯干/头部只做轻微起伏，脚跟贴地。"""
    dx, dy = _zeros()
    s = math.sin(phase)
    c = math.sin(phase + math.pi)
    _add(dx, dy, "front_left", amplitude * s, -amplitude * 1.05 * max(0.0, s))
    _add(dx, dy, "front_right", amplitude * c, -amplitude * 1.05 * max(0.0, c))
    _add(dx, dy, "hind_left", amplitude * 0.62 * c, -amplitude * 0.45 * max(0.0, c))
    _add(dx, dy, "hind_right", amplitude * 0.62 * s, -amplitude * 0.45 * max(0.0, s))
    bounce = abs(math.sin(phase))
    # 前后倾斜让半周期（phase 0 / π）不再长得一样，步态循环更连贯。
    lean = math.cos(phase)
    _add(dx, dy, "body", 3.0 * lean, -2.2 * bounce)
    _add(dx, dy, "head", 4.5 * lean, -2.2 * bounce)
    _add(dx, dy, "tail", 6.0 * math.sin(phase + 0.8), 0.0)
    return dx, dy


def _idle(phase: float, src):
    dx, dy = _zeros()
    breath = 0.5 + 0.5 * math.sin(phase)
    _add(dx, dy, "head", 0.0, -2.4 * breath)
    _add(dx, dy, "body", 0.0, -0.8 * breath)
    _add(dx, dy, "tail", 7.0 * math.sin(phase), 0.0)
    return _field(src, dx, dy)


def _walk(phase: float, src):
    dx, dy = _gait(phase, 19.0)
    return _field(src, dx, dy)


def _run(phase: float, src):
    dx, dy = _gait(phase, 30.0)
    # 前倾：只对上半身施加水平位移，不做整图旋转。
    _add(dx, dy, "head", 4.0, -1.0)
    _add(dx, dy, "body", 2.0, 0.0)
    return _field(src, dx, dy)


def _hop(progress: float, src):
    dx, dy = _zeros()
    arc = math.sin(math.pi * progress)
    # 跳跃是整体位移，允许整图上移；脚部额外收起。
    dy += -34.0 * arc
    _add(dx, dy, "front_left", 0.0, 9.0 * arc)
    _add(dx, dy, "front_right", 0.0, 9.0 * arc)
    _add(dx, dy, "tail", 0.0, -6.0 * arc)
    return _remap(src, _XS - dx, _YS - dy)


def _drop(progress: float, src):
    dx, dy = _zeros()
    settle = math.sin(progress * math.pi * 2) * (1 - progress)
    _add(dx, dy, "body", 0.0, 3.0 * settle)
    _add(dx, dy, "head", 0.0, 2.0 * settle)
    return _field(src, dx, dy)


def _lie(phase: float, src):
    dx, dy = _zeros()
    breath = math.sin(phase)
    _add(dx, dy, "head", 2.0 * breath, 8.0)
    _add(dx, dy, "body", 0.0, 4.0 + 1.2 * breath)
    _add(dx, dy, "front_left", -3.0, 1.0)
    _add(dx, dy, "front_right", 3.0, 1.0)
    return _field(src, dx, dy)


def _talk(phase: float, src):
    dx, dy = _zeros()
    nod = math.sin(phase)
    _add(dx, dy, "mouth", 0.0, 3.0 * (0.5 + 0.5 * nod))
    _add(dx, dy, "head", 0.0, -1.2 * nod)
    # 挥手：只动一只前脚，对应 Petdex 的 waving 行。
    _add(dx, dy, "front_right", 7.0 * nod, -5.0 * max(0.0, nod))
    return _field(src, dx, dy)


def _eat(phase: float, src):
    dx, dy = _zeros()
    dip = 13.0 * (0.5 + 0.5 * math.sin(phase))
    _add(dx, dy, "head", 0.0, dip)
    _add(dx, dy, "mouth", 0.0, dip * 1.15)
    _add(dx, dy, "tail", 4.0 * math.sin(phase), 0.0)
    return _field(src, dx, dy)


def _sleepy(phase: float, src):
    dx, dy = _zeros()
    breath = math.sin(phase)
    _add(dx, dy, "head", 2.5 * breath, 10.0 + 1.5 * breath)
    _add(dx, dy, "body", 0.0, 3.0 + 1.0 * breath)
    return _field(src, dx, dy)


def _angry(phase: float, src):
    dx, dy = _zeros()
    shake = math.sin(phase * 2)
    _add(dx, dy, "head", 4.5 * shake, 0.0)
    _add(dx, dy, "tail", -8.0 * shake, 0.0)
    return _field(src, dx, dy)


def _yaw_frame(src: np.ndarray, theta: float) -> Image.Image:
    """绕垂直轴（Y 轴）转 theta：柱面重映射 + 背面镜像。

    - y 完全不变：脚底贴地，不上下浮动；
    - 没有任何 2D rotation：不会绕图像中心打转；
    - 水平方向按柱面 sin 映射，中间细节保留、边缘透视压缩；
    - 过 90° 后水平镜像表示背面视角。
    """
    cx = SIZE / 2
    half = SIZE / 2
    u = (_XS - cx) / half
    # 把图像看成贴在圆柱面上：x -> 弧长角 phi，再按视角 view 取源。
    # view 控制在 ±0.55 rad 内，保证 sin 单调、不会折叠出横向撕裂。
    phi = np.arcsin(u * 0.92)
    view = 0.55 * math.sin(theta)
    k = 0.78 + 0.22 * abs(math.cos(theta))
    sx = cx + (half / 0.92) * k * np.sin(phi + view)
    if math.cos(theta) < 0:
        sx = SIZE - sx  # 背面视角
    # 越界像素必须透明，否则 np.clip 会把边缘像素横向拉成条纹。
    valid = (sx >= 0) & (sx < SIZE)
    image = _remap(src, np.clip(sx, 0, SIZE - 1), _YS)
    pixels = np.asarray(image).copy()
    pixels[~valid, 3] = 0
    return Image.fromarray(pixels, "RGBA")


BUILDERS = {
    "idle": lambda p, t, src: _idle(p, src),
    "walk": lambda p, t, src: _walk(p, src),
    "run": lambda p, t, src: _run(p, src),
    "hop": lambda p, t, src: _hop(t, src),
    "drop": lambda p, t, src: _drop(t, src),
    "lie": lambda p, t, src: _lie(p, src),
    "talk": lambda p, t, src: _talk(p, src),
    "eat": lambda p, t, src: _eat(p, src),
    "sleepy": lambda p, t, src: _sleepy(p, src),
    "angry": lambda p, t, src: _angry(p, src),
    "spin": lambda p, t, src: _yaw_frame(src, p),
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pet-dir",
        type=Path,
        default=ROOT / "exports" / "有财",
        help="宠物包目录（含 base.png 与 petpack.json）",
    )
    args = parser.parse_args()
    pet_dir: Path = args.pet_dir.resolve()
    pack_path = pet_dir / "petpack.json"
    pack = json.loads(pack_path.read_text(encoding="utf-8"))
    base_file = (pack.get("frames") or {}).get("idle", "base.png")
    base = Image.open(pet_dir / base_file).convert("RGBA")
    if base.size != (SIZE, SIZE):
        base = base.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    src = np.asarray(base, dtype=np.uint8)

    animations = dict(pack.get("animations") or {})
    written = 0
    for key, builder in BUILDERS.items():
        count = FRAME_COUNTS[key]
        files = []
        for index in range(count):
            phase = 2 * math.pi * index / count
            progress = index / max(1, count - 1)
            frame = builder(phase, progress, src)
            name = f"{key}_{index}.png"
            frame.save(pet_dir / name, optimize=True)
            files.append(name)
            written += 1
        animations[key] = {"fps": FPS[key], "frames": files}

    # Petdex 的 run-right / run-left 是两条独立状态行。程序化素材没有侧身画，
    # 这里用倒序帧作为另一方向的独立序列（配合渲染层 facing 镜像），
    # 保证「方向是独立序列」而不是运行时镜像或 2D 旋转。
    for key, mirrored in (("walk", "walk_left"), ("run", "run_left")):
        animations[mirrored] = {
            "fps": FPS[key],
            "frames": list(reversed(animations[key]["frames"])),
        }

    pack["animations"] = animations
    pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{pet_dir.name}: 生成 {written} 帧，动作 {', '.join(BUILDERS)}")
    print(f"petpack.json animations: {', '.join(sorted(animations))}")


if __name__ == "__main__":
    main()
