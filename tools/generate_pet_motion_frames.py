"""为单图宠物包补程序化动作帧（幂等，可重复运行）。

不依赖 ComfyUI / 模型，用 Pillow 对 base.png 做几何变形，产出与原画风格
一致的轻量动作：待机呼吸、说话点头、讨食啃咬、打盹、转圈。

用法：
    python tools/generate_pet_motion_frames.py                # 默认 exports/有财
    python tools/generate_pet_motion_frames.py --pet-dir <目录>

脚本只覆盖自己管理的 animations key（idle / talk / eat / sleepy / spin），
petpack.json 里已有的 walk / run / lie / hop / drop 保持不动。
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512
MANAGED_KEYS = ("idle", "talk", "eat", "sleepy", "spin")


def _canvas() -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def _compose(
    src: Image.Image,
    *,
    scale_x: float = 1.0,
    scale_y: float = 1.0,
    offset_x: float = 0.0,
    offset_y: float = 0.0,
    angle: float = 0.0,
    mirror: bool = False,
) -> Image.Image:
    """缩放 -> 旋转 -> 镜像 -> 居中贴回同尺寸画布（透明背景）。"""
    img = src
    if scale_x != 1.0 or scale_y != 1.0:
        w = max(1, round(SIZE * scale_x))
        h = max(1, round(SIZE * scale_y))
        img = img.resize((w, h), Image.Resampling.LANCZOS)
    if angle:
        img = img.rotate(angle, resample=Image.Resampling.BICUBIC, expand=False)
    if mirror:
        img = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    w, h = img.size
    out = _canvas()
    x = round((SIZE - w) / 2 + offset_x)
    y = round((SIZE - h) / 2 + offset_y)
    out.paste(img, (x, y), img)
    return out


def _warp_rows(src: Image.Image, row_fn) -> Image.Image:
    """按行做垂直方向形变：row_fn(t) -> (dy, scale_x)，t 为归一化 y。

    用于「低头啃食」这类只有上半身动、下半身保持不动的动作。
    """
    out = _canvas()
    for y in range(SIZE):
        t = y / SIZE
        dy, sx = row_fn(t)
        row = src.crop((0, y, SIZE, y + 1))
        x = 0
        if sx != 1.0:
            nw = max(1, round(SIZE * sx))
            row = row.resize((nw, 1), Image.Resampling.BILINEAR)
            x = (SIZE - nw) // 2
        ty = min(SIZE - 1, max(0, round(y + dy)))
        out.paste(row, (x, ty))
    return out


def _idle_frames(base: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(4):
        wave = math.sin(2 * math.pi * i / 4)
        frames.append(
            _compose(
                base,
                scale_x=1 - 0.012 * wave,
                scale_y=1 + 0.022 * wave,
                offset_y=-4 * (0.5 + 0.5 * wave),
            )
        )
    return frames


def _talk_frames(base: Image.Image) -> list[Image.Image]:
    return [
        _compose(base, offset_y=-2, scale_y=1.004),
        _warp_rows(
            base,
            lambda t: (2.5 * max(0.0, 1 - abs(t - 0.62) / 0.18), 1.0)
            if 0.44 < t < 0.8
            else (0.0, 1.0),
        ),
    ]


def _eat_frames(base: Image.Image) -> list[Image.Image]:
    """点头啃食：头部（t<0.55）周期下探，身体不动，配轻微前倾。"""
    depths = (0.0, 1.0, 0.3, 0.8)
    frames = []
    for depth in depths:
        dip = 30.0 * depth

        def row_fn(t: float, dip: float = dip, depth: float = depth):
            if t < 0.56:
                weight = (0.56 - t) / 0.56
                return dip * weight, 1.0 + 0.045 * depth
            return 0.0, 1.0

        frames.append(_compose(_warp_rows(base, row_fn), scale_x=1.015, offset_y=3 * depth))
    return frames


def _sleepy_frames(base: Image.Image) -> list[Image.Image]:
    return [
        _compose(base, scale_x=1.08, scale_y=0.82, offset_y=34, angle=10),
        _compose(base, scale_x=1.085, scale_y=0.835, offset_y=32, angle=8.5),
    ]


def _spin_frames(base: Image.Image) -> list[Image.Image]:
    """原地转圈：靠倾斜 + 小跳 + 半程翻面表达转身，不做极端宽度压缩。

    早期版本用「翻牌」思路把宽度压到 |cos|，90°/270° 那两帧会被压成一根
    100px 宽的竖条（正常约 338px），既不象侧身也不好看。现在最窄只到 0.86，
    每帧都是完整形象；第 4/5 帧之间镜像切换，配合左右倾斜形成转身瞬间。
    """
    angles = (0.0, -9.0, -16.0, -7.0, 7.0, 16.0, 9.0, 0.0)
    lifts = (0.0, -9.0, -18.0, -8.0, -8.0, -18.0, -9.0, 0.0)
    widths = (1.0, 0.94, 0.86, 0.92, 0.92, 0.86, 0.94, 1.0)
    frames = []
    for i in range(8):
        frames.append(
            _compose(
                base,
                scale_x=widths[i],
                scale_y=1 - 0.02 * abs(lifts[i]) / 18,
                offset_y=lifts[i],
                angle=angles[i],
                mirror=i >= 4,
            )
        )
    return frames


BUILDERS = {
    "idle": _idle_frames,
    "talk": _talk_frames,
    "eat": _eat_frames,
    "sleepy": _sleepy_frames,
    "spin": _spin_frames,
}

FPS = {"idle": 6, "talk": 6, "eat": 8, "sleepy": 1.5, "spin": 12}


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

    animations = dict(pack.get("animations") or {})
    written: list[str] = []
    for key, builder in BUILDERS.items():
        files = []
        for index, frame in enumerate(builder(base)):
            name = f"{key}_{index}.png"
            frame.save(pet_dir / name, optimize=True)
            files.append(name)
            written.append(name)
        animations[key] = {"fps": FPS[key], "frames": files}

    pack["animations"] = animations
    pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{pet_dir.name}: 生成 {len(written)} 帧，动作 {', '.join(MANAGED_KEYS)}")
    print(f"petpack.json animations: {', '.join(sorted(animations))}")


if __name__ == "__main__":
    main()
