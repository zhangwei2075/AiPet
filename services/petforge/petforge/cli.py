"""命令行：把照片批量转成宠物包文件夹。

    python -m petforge.cli photo.jpg -o out/ --name 小橘
    python -m petforge.cli photo.jpg -o out/ --animate
    python -m petforge.cli photo.jpg -o out/ --animate --engine comfyui

产物:
    out/<slug>/petpack.json
    out/<slug>/base.png
    out/<slug>/walk_0.png ...      # 加了 --animate
    out/<slug>/atlas.png
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from .animate import AnimateOptions, generate_animation, write_pack_animation
from .pipeline import Options, generate


def _slug(text: str) -> str:
    return re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff_-]+", "_", text).strip("_") or "pet"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="petforge", description="photo -> desktop pet pack")
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("-o", "--out", type=Path, default=Path("pets"))
    parser.add_argument("--style", default="sticker", choices=["sticker", "soft", "original"])
    parser.add_argument("--name", default=None)
    parser.add_argument("--no-remove-bg", action="store_true")
    parser.add_argument("--animate", action="store_true", help="生成 walk/run/lie 动作帧")
    parser.add_argument("--engine", default="procedural", choices=["procedural", "comfyui"])
    parser.add_argument("--comfy-host", default=None, help="ComfyUI 地址，默认 127.0.0.1:8188")
    parser.add_argument("--workflow", type=Path, default=None, help="API 格式工作流 JSON")
    parser.add_argument("--checkpoint", default=None, help="ComfyUI checkpoint 名称")
    parser.add_argument("--subject", default="", help="角色描述，例如 orange hoodie dog")
    parser.add_argument("--atlas", action="store_true", help="额外输出 atlas.png 网格图集")
    args = parser.parse_args(argv)

    comfy_options = None
    if args.engine == "comfyui":
        from .comfy import ComfyOptions

        comfy_options = ComfyOptions(
            host=args.comfy_host or ComfyOptions.host,
            workflow=args.workflow,
            checkpoint=args.checkpoint,
        )

    args.out.mkdir(parents=True, exist_ok=True)
    for source in args.images:
        pet = generate(
            source.read_bytes(),
            Options(style=args.style, name=args.name, remove_bg=not args.no_remove_bg),
        )
        if args.animate:
            result = generate_animation(
                pet.images["base"],
                AnimateOptions(
                    engine=args.engine,
                    atlas=args.atlas,
                    style=args.style,
                    subject=args.subject,
                    comfy=comfy_options,
                ),
            )
            pet.images.update(result.images)
            write_pack_animation(pet.pack, result)
            if result.fallback:
                print(f"[warn] {result.fallback}")

        folder = args.out / _slug(pet.pack["name"])
        folder.mkdir(parents=True, exist_ok=True)
        for filename, blob in pet.images.items():
            (folder / f"{filename}.png").write_bytes(blob)
        (folder / "petpack.json").write_text(
            json.dumps(pet.pack, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        extra = f"  animations={','.join(pet.pack.get('animations', {}))}" if args.animate else ""
        print(
            f"[ok] {source.name} -> {folder}  cutout={pet.pack['metrics']['cutout']}"
            f"  name={pet.pack['name']}{extra}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
