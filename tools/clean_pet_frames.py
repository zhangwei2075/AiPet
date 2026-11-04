"""把 AI 生成的宠物帧清理成可用的真帧动画。

针对「有财」这类图生图产物：
- hop 帧里经常多出一只小狗或小道具：只保留位置最高（跳起）的主体；
- 其他帧去掉面积很小的碎片；
- 统一放到 640 画布，按底边/中心对齐，避免走动时忽大忽小；
- 重建 petpack：walk / run / lie / hop / drop，run 复用 walk 帧并提高 fps。

用法:
    python tools/clean_pet_frames.py <源宠物目录> <输出宠物目录>
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

FRAME_NAMES = [
    "walk_0",
    "walk_1",
    "walk_2",
    "walk_3",
    "hop_0",
    "hop_1",
    "hop_2",
    "hop_3",
    "drop_0",
    "lie_0",
]


def keep_main_component(image: Image.Image, *, hop: bool) -> Image.Image:
    rgba = np.array(image.convert("RGBA"))
    alpha = rgba[:, :, 3]
    binary = (alpha > 127).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(binary, 8)
    if count <= 1:
        return image

    components = [
        (index, int(stats[index, cv2.CC_STAT_AREA]), int(stats[index, cv2.CC_STAT_TOP]))
        for index in range(1, count)
    ]
    if hop:
        # 跳起的那只位置最高；另一只通常是坐在下面的重复主体。
        main = min(components, key=lambda item: item[2])[0]
        keep = {main}
    else:
        main = max(components, key=lambda item: item[1])[0]
        threshold = stats[main, cv2.CC_STAT_AREA] * 0.02
        keep = {index for index, area, _ in components if area >= threshold}

    mask = np.isin(labels, list(keep))
    cleaned = rgba.copy()
    cleaned[~mask] = 0
    return Image.fromarray(cleaned, "RGBA")


def place(frame: Image.Image, size: int, base_bbox: tuple[int, int, int, int], *, hop: bool) -> Image.Image:
    frame = frame.resize((size, size), Image.LANCZOS)
    bbox = frame.getbbox()
    if bbox is None:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))

    center_x = (bbox[0] + bbox[2]) / 2
    base_center_x = (base_bbox[0] + base_bbox[2]) / 2
    left = round(base_center_x - center_x)

    if hop:
        # 保留原图里脚离画布底部的距离，跳起时不要被按回地面。
        bottom = base_bbox[3] - (size - bbox[3])
    else:
        bottom = base_bbox[3]
    top = round(bottom - bbox[3])

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(frame, (left, top))
    return canvas


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2

    source = Path(argv[1])
    target = Path(argv[2])
    target.mkdir(parents=True, exist_ok=True)

    base = Image.open(source / "base.png").convert("RGBA")
    size = base.size[0]
    base_bbox = base.getbbox()
    if base_bbox is None:
        print("base.png 没有前景")
        return 1

    for name in FRAME_NAMES:
        path = source / f"{name}.png"
        if not path.exists():
            continue
        image = Image.open(path).convert("RGBA")
        image = keep_main_component(image, hop=name.startswith("hop"))
        image = place(image, size, base_bbox, hop=name.startswith("hop"))
        image.save(target / f"{name}.png", optimize=True)

    base.save(target / "base.png", optimize=True)

    pack = json.loads((source / "petpack.json").read_text(encoding="utf-8"))
    pack["name"] = "有财（真帧）"
    pack["frames"] = {"idle": "base.png"}
    pack["animations"] = {
        "walk": {"fps": 8, "frames": ["walk_0.png", "walk_1.png", "walk_2.png", "walk_3.png"]},
        # 原来的 run 帧是趴滑姿势，复用 walk 帧并提高帧率更像小跑。
        "run": {"fps": 12, "frames": ["walk_0.png", "walk_1.png", "walk_2.png", "walk_3.png"]},
        "lie": {"fps": 3, "frames": ["drop_0.png", "lie_0.png"]},
        "hop": {"fps": 10, "frames": ["hop_0.png", "hop_1.png", "hop_2.png", "hop_3.png"]},
        "drop": {"fps": 3, "frames": ["drop_0.png"]},
    }
    metrics = pack.setdefault("metrics", {})
    metrics["cutout"] = "cleaned"
    metrics["animate"] = "cleaned"
    (target / "petpack.json").write_text(
        json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"[ok] {source} -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
