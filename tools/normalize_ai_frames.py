"""把 AI 生成的宠物视角图整理成项目可用的透明帧（可重复运行，只依赖 Pillow + numpy + scipy）。

为什么需要这个脚本
------------------
出图模型对 `background: transparent` 的支持**时灵时不灵**，同一套参数会返回三种东西：

| 实际返回 | 处理方式 |
| --- | --- |
| 真透明通道（alpha） | 直接沿用原 alpha —— 模型给的边缘最干净，重新抠反而变差 |
| 纯白底 | 从四角做连通域泛洪，只清与画布边缘连通的白色 |
| **画了棋盘格的假透明** | 棋盘格的亮格是纯白 255、暗格约 220，和白描边同为中性色，需按「中性灰」判定 |

白底和棋盘格都不能「全局白转透明」——白描边贴纸的描边与背景同为白色且**互相连通**，
那样会把狗身上的白色毛发一起吃掉。

对齐
----
新视角底图必须和 `base.png` 保持同样的主体高度占比，否则切换动作时宠物会突然变大变小。
传 `--align-to` 时按参考图的前景高度比例重新缩放并水平居中、底边对齐。

姿态
----
同一动作里混用的视角必须**姿态一致**。`base.png` 是坐姿，所以转身要配坐姿视角
（`*_sit_*`）；走路用的是四足站姿视角（`side_raw`），两者不可互换，
否则转圈中途会从坐姿跳成站姿。

用法：
    # 单张
    python tools/normalize_ai_frames.py exports/有财/_ai/side_raw.png

    # 批量 + 对齐到主帧
    python tools/normalize_ai_frames.py exports/有财/_ai/*.png --align-to exports/有财/base.png

输出写到 `--out-dir`（缺省与源文件同目录），文件名加 `_cut` 后缀，已存在则覆盖。
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

SIZE = 512


def flood(cand: np.ndarray) -> np.ndarray:
    """从四角沿 `cand`（True = 背景候选）泛洪，返回背景 mask。"""
    h, w = cand.shape
    bg = np.zeros((h, w), bool)
    queue: deque[tuple[int, int]] = deque()
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if cand[y, x] and not bg[y, x]:
            bg[y, x] = True
            queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and cand[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                queue.append((nx, ny))

    return bg


def background_mask(rgb: Image.Image, tol: int) -> tuple[np.ndarray, str]:
    """判定背景。返回 (背景 mask, 策略名)。

    纯白底和棋盘格底要分开处理：棋盘格的暗格亮度只有 ~220，
    用白色容差泛洪会卡在暗格上，几乎什么都清不掉。
    """
    arr = np.array(rgb).astype(np.int16)
    corner = arr[0:8, 0:8].reshape(-1, 3).mean(axis=0)
    spread = float(corner.max() - corner.min())

    if corner.mean() >= 239 and spread <= 12:
        cand = (np.abs(arr - 255) <= tol).all(axis=2)
        return flood(cand), "白底泛洪"

    # 棋盘格 / 中性灰底：亮格 255、暗格 ~220，两者都是中性灰（R=G=B）。
    mx = arr.max(axis=2)
    mn = arr.min(axis=2)
    lum = arr.mean(axis=2)
    cand = ((mx - mn) <= 6) & (lum >= 210)
    return flood(cand), "棋盘格/灰底泛洪"


def drop_specks(fg: np.ndarray, min_ratio: float = 0.01) -> np.ndarray:
    """丢掉面积小于最大前景 `min_ratio` 的孤立碎块。

    棋盘格的角落常留下一两个像素的残点，虽然肉眼看不见，
    但会把 bbox 拉到画布边缘，让对齐缩放整体算错。
    """
    labels, count = ndimage.label(fg)
    if count <= 1:
        return fg
    sizes = ndimage.sum(fg, labels, range(1, count + 1))
    threshold = sizes.max() * min_ratio
    keep = np.zeros_like(fg)
    for index, size in enumerate(sizes, start=1):
        if size >= threshold:
            keep |= labels == index
    return keep


def foreground_ratio(im: Image.Image) -> tuple[float, tuple[int, int, int, int]]:
    """前景（alpha > 8）的高度占比与 bbox。"""
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox is None:
        return 0.0, (0, 0, im.width, im.height)
    return (bbox[3] - bbox[1]) / im.height, bbox


def has_native_alpha(src: Path) -> bool:
    """源图是否已自带真实的透明通道。"""
    with Image.open(src) as im:
        return im.mode in ("RGBA", "LA") and im.getchannel("A").getextrema()[0] < 250


def load_on_white(src: Path) -> Image.Image:
    """读成白底 RGB。已经自带透明通道的帧要先合成到白底，否则会压成黑底。"""
    im = Image.open(src).convert("RGBA")
    if im.getchannel("A").getextrema()[0] < 250:
        white = Image.new("RGB", im.size, (255, 255, 255))
        white.paste(im, mask=im.getchannel("A"))
        return white
    return im.convert("RGB")


def cutout(src: Path, size: int, tol: int, feather: float) -> tuple[Image.Image, str]:
    """统一成透明帧，返回 (图像, 去背策略)。

    三条路都先把图合成到白底再缩放，避免非预乘 resize 让透明像素的黑色渗到轮廓上。
    """
    rgb = load_on_white(src).resize((size, size), Image.LANCZOS)

    if has_native_alpha(src):
        with Image.open(src) as im:
            mask = im.convert("RGBA").getchannel("A").resize((size, size), Image.LANCZOS)
        how = "原生 alpha"
    else:
        bg, how = background_mask(rgb, tol)
        fg = drop_specks(~bg)
        mask = Image.fromarray(np.where(fg, 255, 0).astype(np.uint8))

    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))

    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out, how


def align(im: Image.Image, ref_ratio: float) -> Image.Image:
    """把主体高度缩放到参考比例，水平居中、底边对齐。"""
    ratio, _ = foreground_ratio(im)
    if ratio <= 0 or ref_ratio <= 0:
        return im

    scale = ref_ratio / ratio
    if abs(scale - 1.0) < 0.01:
        return im

    w, h = im.size
    scaled = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    _, sbbox = foreground_ratio(scaled)
    cx = (sbbox[0] + sbbox[2]) / 2
    bottom = sbbox[3]

    canvas = Image.new("RGBA", im.size, (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (int(w / 2 - cx), int(h - bottom)))
    return canvas


def main() -> None:
    ap = argparse.ArgumentParser(description="把 AI 生成的视角图整理成透明帧")
    ap.add_argument("src", nargs="+", type=Path, help="源图（支持多个）")
    ap.add_argument("--out-dir", type=Path, default=None, help="输出目录，缺省与源图同目录")
    ap.add_argument("--size", type=int, default=SIZE, help=f"输出边长，缺省 {SIZE}")
    ap.add_argument("--tol", type=int, default=16, help="白色容差，缺省 16")
    ap.add_argument("--feather", type=float, default=0.8, help="alpha 羽化半径，缺省 0.8")
    ap.add_argument("--align-to", type=Path, default=None, help="参考帧，按它的主体高度占比对齐")
    args = ap.parse_args()

    ref_ratio = 0.0
    if args.align_to:
        ref, _ = cutout(args.align_to, args.size, args.tol, args.feather)
        ref_ratio, _ = foreground_ratio(ref)
        print(f"参考主体高度占比 {ref_ratio:.3f}（{args.align_to.name}）")

    failures: list[str] = []
    for src in args.src:
        if not src.exists():
            print(f"跳过（不存在）：{src}")
            continue

        im, how = cutout(src, args.size, args.tol, args.feather)
        if ref_ratio:
            im = align(im, ref_ratio)

        ratio, bbox = foreground_ratio(im)
        covered = 1.0 - (np.array(im.getchannel("A")) > 8).mean()
        if covered < 0.15:
            failures.append(src.name)
            print(f"✗ {src.name}  背景只清掉 {covered:.0%}，去背失败（{how}）")
            continue

        out_dir = args.out_dir or src.parent
        out_dir.mkdir(parents=True, exist_ok=True)
        dst = out_dir / f"{src.stem}_cut.png"
        im.save(dst)
        print(
            f"{dst.name}  {im.size}  主体高度占比 {ratio:.3f}  "
            f"bbox {bbox}  透明 {covered:.0%}  去背={how}"
        )

    if failures:
        raise SystemExit(
            f"有 {len(failures)} 张去背失败：{', '.join(failures)}\n"
            "多半是模型换了一种看不见的底色（例如非中性灰或有纹理的背景）。"
            "用 --tol 调宽容差，或重新出图时明确要求 plain solid white background。"
        )


if __name__ == "__main__":
    main()
