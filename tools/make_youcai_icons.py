#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""从「有财」立绘生成桌面端全部应用图标（幂等，可反复运行）。

源图：``exports/有财/base.png`` —— 640x640 带透明通道的贴纸风小狗（橙卫衣）。
产物（每次运行全部覆盖，不追加、不改源图）：

============================================  ==========================================
路径                                          用途
============================================  ==========================================
app/assets/icons/app_icon.png                 托盘图标 / MSIX logo / pubspec logo_path
app/assets/icons/app_icon.ico                 单文件 exe 的 --icon
app/assets/icons/tray.ico                     历史文件名，保留同步
app/windows/runner/resources/app_icon.ico     Windows 任务栏 / 窗口图标（IDI_APP_ICON）
============================================  ==========================================

托盘图标用 ``ImageAsset.fromAsset('assets/icons/app_icon.png')`` 直接加载；
任务栏图标由 ``Runner.rc`` 的 ``IDI_APP_ICON`` 从 runner 资源里读取。
两者共用同一张母版，保证托盘与任务栏看到的是同一只「有财」。

运行（本机 Pillow 在 petforge venv 里，系统 python 没装 Pillow）::

    services/petforge/.venv/Scripts/python.exe tools/make_youcai_icons.py
    services/petforge/.venv/Scripts/python.exe tools/make_youcai_icons.py --preview

``--preview`` 只把候选样式写到 ``.tmp/icon-preview/``，不覆盖正式图标。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "exports" / "有财" / "base.png"

PNG_OUT = ROOT / "app" / "assets" / "icons" / "app_icon.png"
ICO_OUTS = (
    ROOT / "app" / "assets" / "icons" / "app_icon.ico",
    ROOT / "app" / "assets" / "icons" / "tray.ico",
    ROOT / "app" / "windows" / "runner" / "resources" / "app_icon.ico",
)
PREVIEW_DIR = ROOT / ".tmp" / "icon-preview"

PNG_SIZE = 256
ICO_SIZES = (16, 20, 24, 32, 48, 64, 128, 256)

# 暖色底板：上奶油、下蜜桃，呼应橙卫衣，托盘小尺寸也不会糊成一团。
GRADIENT_TOP = (255, 250, 242)
GRADIENT_BOTTOM = (255, 224, 190)
BORDER_COLOR = (240, 203, 159, 255)


def load_pet() -> Image.Image:
    """抠出非透明区域，去掉原图四周大片留白。"""
    with Image.open(SOURCE) as raw:
        pet = raw.convert("RGBA")
    bbox = pet.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError(f"源图没有非透明像素：{SOURCE}")
    return pet.crop(bbox)


def gradient(size: int) -> Image.Image:
    """竖向渐变，用 1 像素宽的条带拉伸，避免逐像素画大图。"""
    strip = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        strip.putpixel(
            (0, y),
            tuple(round(a + (b - a) * t) for a, b in zip(GRADIENT_TOP, GRADIENT_BOTTOM)),
        )
    return strip.resize((size, size), Image.Resampling.BILINEAR).convert("RGBA")


def card_background(size: int) -> Image.Image:
    """圆角方形底板 + 一圈细描边，底板外保持透明。"""
    inset = max(1, round(size * 0.025))
    radius = round(size * 0.22)
    box = (inset, inset, size - 1 - inset, size - 1 - inset)

    # 32px 以下用纯奶油底：渐变和描边在小图标里只会变成噪点。
    bg = gradient(size) if size > 32 else Image.new("RGBA", (size, size), (*GRADIENT_TOP, 255))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    bg.putalpha(mask)

    if size > 32:
        outline = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(outline).rounded_rectangle(
            box,
            radius=radius,
            outline=BORDER_COLOR,
            width=max(1, round(size * 0.006)),
        )
        bg.alpha_composite(outline)
    return bg


def compose(size: int, variant: str = "card") -> Image.Image:
    """生成某个尺寸下的完整图标。

    ``card``    —— 暖色圆角底板 + 全身立绘（正式样式）
    ``sticker`` —— 透明底 + 立绘
    ``circle``  —— 圆形暖色底板 + 立绘（预览候选）

    小尺寸（<=32px）改用头部特写，托盘里才看得清脸；大尺寸保留全身。
    """
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if variant == "card":
        canvas = card_background(size)
    elif variant == "circle":
        bg = gradient(size)
        mask = Image.new("L", (size, size), 0)
        inset = max(1, round(size * 0.025))
        ImageDraw.Draw(mask).ellipse((inset, inset, size - 1 - inset, size - 1 - inset), fill=255)
        bg.putalpha(mask)
        canvas = bg

    pet = load_pet()
    if size <= 24:
        # 16/20/24px：只留脸，眼睛鼻子才占得住像素
        pet = pet.crop((0, 0, pet.width, round(pet.height * 0.47)))
        fill = 1.0
    elif size <= 32:
        # 32px：头 + 肩
        pet = pet.crop((0, 0, pet.width, round(pet.height * 0.56)))
        fill = 0.98
    else:
        fill = 0.86 if variant != "sticker" else 0.98

    scale = (size * fill) / max(pet.width, pet.height)
    target = (
        max(1, round(pet.width * scale)),
        max(1, round(pet.height * scale)),
    )
    pet = pet.resize(target, Image.Resampling.LANCZOS)

    x = (size - target[0]) // 2
    y = (size - target[1]) // 2 + round(size * 0.015)
    canvas.alpha_composite(pet, (x, y))
    return canvas


def write_ico(path: Path) -> None:
    """每个尺寸单独渲染后打包成多帧 ICO，避免系统从小图直接放大。"""
    frames = {s: compose(s) for s in ICO_SIZES}
    path.parent.mkdir(parents=True, exist_ok=True)
    frames[PNG_SIZE].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=[frames[s] for s in ICO_SIZES if s != PNG_SIZE],
    )


def preview() -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for variant in ("card", "sticker", "circle"):
        compose(256, variant).save(PREVIEW_DIR / f"youcai_{variant}_256.png")
        compose(32, variant).save(PREVIEW_DIR / f"youcai_{variant}_32.png")
        compose(16, variant).save(PREVIEW_DIR / f"youcai_{variant}_16.png")
    print(f"预览已写入：{PREVIEW_DIR}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true", help="只生成候选预览，不覆盖正式图标")
    args = parser.parse_args()
    if args.preview:
        preview()
        return

    if not SOURCE.exists():
        raise SystemExit(f"找不到有财立绘：{SOURCE}")

    PNG_OUT.parent.mkdir(parents=True, exist_ok=True)
    compose(PNG_SIZE).save(PNG_OUT, format="PNG")
    print(f"PNG  {PNG_OUT.relative_to(ROOT)}  {PNG_SIZE}x{PNG_SIZE}")
    for path in ICO_OUTS:
        write_ico(path)
        print(f"ICO  {path.relative_to(ROOT)}  {len(ICO_SIZES)} 帧")


if __name__ == "__main__":
    main()
