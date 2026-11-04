"""用 ComfyUI + IP-Adapter 精修现有宠物帧。

不重新发明姿势：以已经对齐的 walk/hop/lie 帧作为 img2img 底图，IP-Adapter 锁住
角色外形，低 denoise 只修画风、描边和细节。这样既保留真实动作，又能把 AI 生成
的瑕疵（两只狗、比例漂移）修掉。

用法:
    python tools/refine_pet_frames.py <源宠物目录> <输出宠物目录>
"""

from __future__ import annotations

import io
import json
import sys
from pathlib import Path

from PIL import Image

from petforge.animate import align_like_base, apply_sticker_style
from petforge.comfy import ComfyOptions, generate_frame
from petforge.pipeline import remove_background

SUBJECT = (
    "a cute cartoon schnauzer dog wearing an orange hoodie, grey and white fur, "
    "floppy ears, 2d sticker illustration, clean white outline, white background, "
    "same character, consistent markings"
)

PLAN = [
    ("walk_0", "walk_0", "walking, one front paw lifted", 0.40),
    ("walk_1", "walk_1", "walking, mid stride, paws apart", 0.40),
    ("walk_2", "walk_2", "walking, other front paw lifted", 0.40),
    ("walk_3", "walk_3", "walking, paws together", 0.40),
    ("hop_0", "hop_0", "jumping in the air, paws tucked, happy", 0.35),
    ("hop_1", "hop_1", "jumping high, paws up, cheerful", 0.35),
    ("hop_2", "hop_2", "jumping in the air, body stretched", 0.35),
    ("hop_3", "hop_3", "jumping, paws tucked, excited", 0.35),
    ("drop_0", "drop_0", "lying down on the ground, relaxed", 0.35),
    ("lie_0", "lie_0", "lying down, belly on the floor, happy", 0.35),
]


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2

    source = Path(argv[1])
    target = Path(argv[2])
    target.mkdir(parents=True, exist_ok=True)

    base = Image.open(source / "base.png").convert("RGBA")
    options = ComfyOptions(
        host="http://127.0.0.1:8188",
        workflow=Path(__file__).resolve().parent.parent / "services/petforge/workflows/img2img_ipadapter.api.json",
        timeout=600,
        steps=20,
        cfg=6.5,
    )

    for index, (source_name, output_name, action, denoise) in enumerate(PLAN):
        frame = Image.open(source / f"{source_name}.png").convert("RGBA")
        flat = Image.new("RGB", frame.size, (255, 255, 255))
        flat.paste(frame, mask=frame.getchannel("A"))
        buffer = io.BytesIO()
        flat.save(buffer, format="PNG")

        data = generate_frame(
            buffer.getvalue(),
            prompt=f"{SUBJECT}, {action}",
            seed=20261101 + index * 97,
            options=ComfyOptions(
                host=options.host,
                workflow=options.workflow,
                timeout=options.timeout,
                steps=options.steps,
                cfg=options.cfg,
                denoise=denoise,
            ),
        )
        result = Image.open(io.BytesIO(data)).convert("RGBA")
        cut, _method = remove_background(result, allow_rembg=False)
        aligned = align_like_base(cut, base)
        aligned = apply_sticker_style(aligned, outline_px=10)
        aligned.save(target / f"{output_name}.png", optimize=True)
        print(f"[ok] {output_name}")

    base.save(target / "base.png", optimize=True)

    pack = json.loads((source / "petpack.json").read_text(encoding="utf-8"))
    pack["name"] = "有财（AI 精修）"
    pack["frames"] = {"idle": "base.png"}
    pack["animations"] = {
        "walk": {"fps": 8, "frames": ["walk_0.png", "walk_1.png", "walk_2.png", "walk_3.png"]},
        "run": {"fps": 12, "frames": ["walk_0.png", "walk_1.png", "walk_2.png", "walk_3.png"]},
        "hop": {"fps": 10, "frames": ["hop_0.png", "hop_1.png", "hop_2.png", "hop_3.png"]},
        "lie": {"fps": 3, "frames": ["drop_0.png", "lie_0.png"]},
        "drop": {"fps": 3, "frames": ["drop_0.png"]},
    }
    metrics = pack.setdefault("metrics", {})
    metrics["cutout"] = "comfyui"
    metrics["animate"] = "comfyui-ipadapter"
    (target / "petpack.json").write_text(
        json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"[ok] {source} -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
