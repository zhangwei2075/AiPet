"""照片 -> 宠物贴纸 的核心图像管线。

策略链（按质量从高到低，失败自动降级）：
1. rembg（可选依赖，u2net 抠图，质量最好）
2. 纯色背景 flood-fill（证件照 / 白底图效果极好）
3. OpenCV GrabCut（通用照片，假设主体大致居中）
4. 椭圆遮罩（兜底，保证永远有可用结果）

输出统一为「正方形透明 PNG + 贴纸描边」，并附带调色板、头部锚点等元数据。
"""

from __future__ import annotations

import base64
import io
from dataclasses import dataclass, field
from typing import Any

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from .persona import build_persona

SQUARE_SIZE = 640
MAX_INPUT = 1400


@dataclass
class Options:
    style: str = "sticker"  # sticker | soft | original
    size: int = SQUARE_SIZE
    remove_bg: bool = True
    outline: int = 10
    name: str | None = None


@dataclass
class GeneratedPet:
    pack: dict[str, Any]
    images: dict[str, bytes] = field(default_factory=dict)

    def pack_with_base64(self) -> dict[str, Any]:
        data = dict(self.pack)
        data["images"] = {
            key: {"mimeType": "image/png", "data": base64.b64encode(value).decode("ascii")}
            for key, value in self.images.items()
        }
        return data


# --------------------------------------------------------------------------- #
# 读取 / 基础处理
# --------------------------------------------------------------------------- #


def load_image(data: bytes) -> Image.Image:
    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA")
    if max(img.size) > MAX_INPUT:
        ratio = MAX_INPUT / max(img.size)
        img = img.resize((round(img.width * ratio), round(img.height * ratio)), Image.LANCZOS)
    return img


def _border_std(rgb: np.ndarray, width: int = 3) -> float:
    strips = [
        rgb[:width, :, :].reshape(-1, 3),
        rgb[-width:, :, :].reshape(-1, 3),
        rgb[:, :width, :].reshape(-1, 3),
        rgb[:, -width:, :].reshape(-1, 3),
    ]
    border = np.concatenate(strips, axis=0).astype(np.float32)
    return float(border.std(axis=0).mean())


def _clean_alpha(alpha: np.ndarray, min_area_ratio: float = 0.02) -> np.ndarray:
    """去掉碎块、填补内部空洞、轻微羽化。"""
    binary = (alpha > 127).astype(np.uint8) * 255
    kernel = np.ones((3, 3), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel, iterations=2)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(binary, 8)
    if count > 1:
        areas = stats[1:, cv2.CC_STAT_AREA]
        keep = np.zeros_like(binary)
        largest = int(areas.max())
        for idx, area in enumerate(areas, start=1):
            if area >= max(32, largest * min_area_ratio):
                keep[labels == idx] = 255
        binary = keep

    # 填洞：从角落洪泛背景，没被淹到且原本是背景的像素就是洞
    h, w = binary.shape
    flood = binary.copy()
    mask = np.zeros((h + 2, w + 2), np.uint8)
    cv2.floodFill(flood, mask, (0, 0), 255)
    holes = ((flood == 0) & (binary == 0)).astype(np.uint8) * 255
    binary = cv2.bitwise_or(binary, holes)

    feathered = cv2.GaussianBlur(binary, (0, 0), 1.1)
    return np.clip(feathered.astype(np.float32) * 1.12, 0, 255).astype(np.uint8)


def _flat_background_cut(img: Image.Image) -> Image.Image:
    rgb = np.array(img.convert("RGB"))
    h, w = rgb.shape[:2]
    border = np.concatenate(
        [rgb[:3].reshape(-1, 3), rgb[-3:].reshape(-1, 3), rgb[:, :3].reshape(-1, 3), rgb[:, -3:].reshape(-1, 3)]
    )
    bg = np.median(border, axis=0)
    distance = np.linalg.norm(rgb.astype(np.float32) - bg[None, None, :], axis=2)
    alpha = (distance > 26).astype(np.uint8) * 255
    alpha = _clean_alpha(alpha)
    out = img.convert("RGBA")
    out.putalpha(Image.fromarray(alpha))
    return out


def _grabcut_cut(img: Image.Image) -> Image.Image:
    rgb = np.array(img.convert("RGB"))
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    h, w = bgr.shape[:2]
    # 用「中心先验」初始化：中间椭圆大概率是主体，四周一圈确定是背景。
    # 比单纯 GC_INIT_WITH_RECT 更抗渐变 / 花纹背景。
    mask = np.full((h, w), cv2.GC_BGD, np.uint8)
    mask[int(h * 0.03) : int(h * 0.97), int(w * 0.03) : int(w * 0.97)] = cv2.GC_PR_BGD
    ellipse = np.zeros((h, w), np.uint8)
    cv2.ellipse(ellipse, (w // 2, int(h * 0.55)), (int(w * 0.23), int(h * 0.29)), 0, 0, 360, 255, -1)
    mask[ellipse > 0] = cv2.GC_PR_FGD
    mask[: int(h * 0.015), :] = cv2.GC_BGD
    mask[int(h * 0.985) :, :] = cv2.GC_BGD
    mask[:, : int(w * 0.015)] = cv2.GC_BGD
    mask[:, int(w * 0.985) :] = cv2.GC_BGD

    bgd = np.zeros((1, 65), np.float64)
    fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, mask, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    alpha = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    alpha = _clean_alpha(alpha)
    out = img.convert("RGBA")
    out.putalpha(Image.fromarray(alpha))
    return out


def _mask_quality(rgba: Image.Image) -> tuple[float, float]:
    """(边缘前景占比, 中心前景占比)。边缘太多说明背景被吃进来了。"""
    alpha = np.array(rgba.getchannel("A")) > 127
    h, w = alpha.shape
    band = max(2, int(min(h, w) * 0.012))
    border = np.concatenate(
        [alpha[:band].ravel(), alpha[-band:].ravel(), alpha[:, :band].ravel(), alpha[:, -band:].ravel()]
    )
    cy, cx = h // 2, w // 2
    ry, rx = max(2, int(h * 0.05)), max(2, int(w * 0.05))
    center = alpha[cy - ry : cy + ry, cx - rx : cx + rx]
    return float(border.mean()), float(center.mean())


def _oval_cut(img: Image.Image) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse((w * 0.04, h * 0.02, w * 0.96, h * 0.98), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(max(1, w // 180)))
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def _rembg_cut(img: Image.Image) -> Image.Image | None:
    try:
        from rembg import remove  # type: ignore
    except Exception:
        return None
    try:
        result = remove(img.convert("RGB"))
        return result.convert("RGBA")
    except Exception:
        return None


def _foreground_ratio(rgba: Image.Image) -> float:
    alpha = np.array(rgba.getchannel("A"))
    return float((alpha > 127).mean())


def _kmeans_centers(pixels: np.ndarray, k: int = 6) -> np.ndarray:
    if len(pixels) > 8000:
        idx = np.random.default_rng(11).choice(len(pixels), 8000, replace=False)
        pixels = pixels[idx]
    data = pixels.astype(np.float32)
    k = min(k, max(1, len(data) // 20))
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0)
    _, _, centers = cv2.kmeans(data, k, None, criteria, 2, cv2.KMEANS_PP_CENTERS)
    return centers


def _nearest_dist(lab: np.ndarray, centers: np.ndarray) -> np.ndarray:
    best = np.full(lab.shape[:2], np.inf, dtype=np.float32)
    for center in centers:
        dist = np.sum((lab - center[None, None, :]) ** 2, axis=2)
        np.minimum(best, dist, out=best)
    return best


def _color_refine(rgba: Image.Image) -> Image.Image:
    """用前景/背景的颜色分布再切一刀，去掉 GrabCut 吃进来的背景块。"""
    alpha = np.array(rgba.getchannel("A"))
    fg = cv2.erode((alpha > 127).astype(np.uint8), np.ones((9, 9), np.uint8))
    bg = (alpha == 0).astype(np.uint8)
    if fg.sum() < 400 or bg.sum() < 400:
        return rgba

    small = rgba.resize((max(64, rgba.width // 2), max(64, rgba.height // 2)), Image.BILINEAR)
    rgb = np.array(small.convert("RGB"))
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    fg_small = cv2.resize(fg, (lab.shape[1], lab.shape[0]), interpolation=cv2.INTER_NEAREST)
    bg_small = cv2.resize(bg, (lab.shape[1], lab.shape[0]), interpolation=cv2.INTER_NEAREST)

    fg_centers = _kmeans_centers(lab[fg_small > 0])
    bg_centers = _kmeans_centers(lab[bg_small > 0])
    keep = (_nearest_dist(lab, fg_centers) <= _nearest_dist(lab, bg_centers) * 1.15).astype(np.uint8) * 255
    keep = cv2.resize(keep, rgba.size, interpolation=cv2.INTER_LINEAR)
    refined = np.minimum(alpha, keep)
    refined = _clean_alpha(refined)
    out = rgba.copy()
    out.putalpha(Image.fromarray(refined))
    return out


def _accept(rgba: Image.Image) -> bool:
    border, center = _mask_quality(rgba)
    ratio = _foreground_ratio(rgba)
    return border < 0.32 and center > 0.55 and 0.03 < ratio < 0.95


def remove_background(img: Image.Image, *, allow_rembg: bool = True, allow_grabcut: bool = True) -> tuple[Image.Image, str]:
    """返回 (抠图结果, 使用的方法名)。"""
    rgb = np.array(img.convert("RGB"))
    border_std = _border_std(rgb)
    is_flat = border_std < 9.0

    if allow_rembg:
        result = _rembg_cut(img)
        if result is not None and _accept(result):
            return result, "rembg"

    if is_flat:
        result = _flat_background_cut(img)
        if _accept(result):
            return result, "flat"

    if allow_grabcut:
        try:
            result = _grabcut_cut(img)
            refined = _color_refine(result)
            if _accept(refined):
                return refined, "grabcut"
            if _accept(result):
                return result, "grabcut"
        except Exception:
            pass

    return _oval_cut(img), "oval"


# --------------------------------------------------------------------------- #
# 贴纸化
# --------------------------------------------------------------------------- #


def _enhance_colors(rgba: Image.Image, saturation: float = 1.16, contrast: float = 1.04) -> Image.Image:
    rgb = np.array(rgba.convert("RGB")).astype(np.float32) / 255.0
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    hsv[..., 1] = np.clip(hsv[..., 1] * saturation, 0, 1)
    hsv[..., 2] = np.clip(hsv[..., 2] * contrast, 0, 1)
    enhanced = cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)
    out = Image.fromarray((enhanced * 255).clip(0, 255).astype(np.uint8)).convert("RGBA")
    out.putalpha(rgba.getchannel("A"))
    return out


def apply_sticker_style(rgba: Image.Image, outline_px: int = 12) -> Image.Image:
    """白色描边 + 深色外圈，让宠物在任意桌面壁纸上都清晰。"""
    size = rgba.size
    alpha = np.array(rgba.getchannel("A"))
    solid = (alpha > 110).astype(np.uint8) * 255
    solid = cv2.morphologyEx(solid, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), iterations=1)
    solid = cv2.GaussianBlur(solid, (0, 0), 0.6)

    k = max(3, int(outline_px / 640 * size[0]) | 1)
    k2 = k + max(3, k // 2)
    round_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    round_k2 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k2, k2))
    dilate = cv2.dilate(solid, round_k, iterations=1)
    dilate2 = cv2.dilate(solid, round_k2, iterations=1)

    white_alpha = np.clip(dilate.astype(np.int16) - alpha.astype(np.int16), 0, 255).astype(np.uint8)
    dark_alpha = (np.clip(dilate2.astype(np.int16) - dilate.astype(np.int16), 0, 255) * 0.5).astype(np.uint8)

    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    dark = Image.new("RGBA", size, (58, 40, 34, 255))
    dark.putalpha(Image.fromarray(dark_alpha))
    white = Image.new("RGBA", size, (255, 255, 255, 255))
    white.putalpha(Image.fromarray(white_alpha))
    canvas.alpha_composite(dark)
    canvas.alpha_composite(white)
    canvas.alpha_composite(rgba)
    return canvas


def _smooth_alpha(rgba: Image.Image) -> Image.Image:
    """去掉抠图边缘的孤立噪点，再做 1px 抗锯齿。"""
    alpha = np.array(rgba.getchannel("A"))
    alpha = cv2.medianBlur(alpha, 5)
    alpha = cv2.morphologyEx(alpha, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8), iterations=1)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 1.0)
    out = rgba.copy()
    out.putalpha(Image.fromarray(np.clip(alpha.astype(np.float32) * 1.1, 0, 255).astype(np.uint8)))
    return out


def fit_square(rgba: Image.Image, size: int, margin_ratio: float = 0.035) -> tuple[Image.Image, dict[str, float]]:
    bbox = rgba.getbbox() or (0, 0, rgba.width, rgba.height)
    crop = rgba.crop(bbox)
    inner = size * (1 - 2 * margin_ratio)
    scale = inner / max(crop.width, crop.height)
    new_size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    crop = crop.resize(new_size, Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ox, oy = (size - new_size[0]) // 2, (size - new_size[1]) // 2
    canvas.alpha_composite(crop, (ox, oy))
    metrics = {
        "sourceBBox": [float(v) for v in bbox],
        "scale": scale,
        "offsetX": float(ox),
        "offsetY": float(oy),
        "size": float(size),
    }
    return canvas, metrics


def map_point(point: tuple[float, float], metrics: dict[str, float], size: int) -> tuple[float, float]:
    x0, y0 = metrics["sourceBBox"][0], metrics["sourceBBox"][1]
    return (
        ((point[0] - x0) * metrics["scale"] + metrics["offsetX"]) / size,
        ((point[1] - y0) * metrics["scale"] + metrics["offsetY"]) / size,
    )


def detect_head(img: Image.Image) -> tuple[tuple[float, float], float] | None:
    try:
        cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        cascade = cv2.CascadeClassifier(cascade_path)
        gray = np.array(img.convert("L"))
        gray = cv2.resize(gray, (gray.shape[1] // 2, gray.shape[0] // 2))
        faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(40, 40))
        if len(faces) == 0:
            return None
        x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
        point = ((x + w / 2) * 2, (y + h / 2) * 2)
        return point, float(max(w, h) * 2 * 1.15)
    except Exception:
        return None


def extract_palette(rgba: Image.Image, k: int = 5) -> list[str]:
    arr = np.array(rgba.convert("RGB"))
    alpha = np.array(rgba.getchannel("A"))
    pixels = arr[alpha > 200]
    if len(pixels) < k * 4:
        pixels = arr.reshape(-1, 3)
    if len(pixels) > 20000:
        idx = np.random.default_rng(7).choice(len(pixels), 20000, replace=False)
        pixels = pixels[idx]
    data = pixels.astype(np.float32)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 12, 1.0)
    _, labels, centers = cv2.kmeans(data, k, None, criteria, 3, cv2.KMEANS_PP_CENTERS)
    counts = np.bincount(labels.flatten(), minlength=k)
    order = np.argsort(-counts)
    palette: list[str] = []
    for i in order:
        r, g, b = (int(round(c)) for c in centers[i])
        palette.append(f"#{r:02x}{g:02x}{b:02x}")
    return palette


def _dominant_saturated(palette: list[str]) -> str:
    best, best_score = palette[0], -1.0
    for color in palette:
        raw = color.lstrip("#")
        r, g, b = (int(raw[i : i + 2], 16) / 255 for i in (0, 2, 4))
        mx, mn = max(r, g, b), min(r, g, b)
        s = 0 if mx == 0 else (mx - mn) / mx
        score = s * (0.4 + mx)
        if score > best_score:
            best, best_score = color, score
    return best


# --------------------------------------------------------------------------- #
# 对外主入口
# --------------------------------------------------------------------------- #


def generate(data: bytes, options: Options | None = None) -> GeneratedPet:
    options = options or Options()
    original = load_image(data)
    method = "none"

    if options.remove_bg:
        cut, method = remove_background(original)
    else:
        cut = original.convert("RGBA")
        cut.putalpha(Image.new("L", cut.size, 255))

    # 清掉完全透明的边角，再统一裁切到正方形
    square, metrics = fit_square(_smooth_alpha(cut), options.size)
    if options.style == "sticker":
        square = apply_sticker_style(square, outline_px=options.outline)
        # 描边会略微溢出，二次裁切保证不出画布
        square = square.crop((0, 0, options.size, options.size))
    elif options.style == "soft":
        square = _enhance_colors(square, saturation=1.06, contrast=1.02)

    palette = extract_palette(square)
    auto_name = build_persona(([_dominant_saturated(palette)] + palette)[:5])
    persona = dict(auto_name)
    if options.name:
        persona["name"] = options.name
        persona["greeting"] = auto_name["greeting"].replace(auto_name["name"], options.name, 1)
        persona["systemPrompt"] = auto_name["systemPrompt"].replace(
            f"「{auto_name['name']}」", f"「{options.name}」", 1
        )

    height_ratio = 0.0
    alpha = np.array(square.getchannel("A"))
    rows = np.where(alpha.max(axis=1) > 100)[0]
    if len(rows):
        height_ratio = float(rows[-1] - rows[0]) / options.size

    head = detect_head(original)
    if head is not None:
        head_center, head_radius = head
        hx, hy = map_point(head_center, metrics, options.size)
        head_anchor = [round(hx, 4), round(hy, 4)]
        head_radius_ratio = round(min(0.55, head_radius * metrics["scale"] / options.size), 4)
    else:
        head_anchor = [0.5, 0.24]
        head_radius_ratio = 0.26

    pack: dict[str, Any] = {
        "schemaVersion": 1,
        "name": persona["name"],
        "personality": {
            "traits": persona["traits"],
            "tone": persona["tone"],
            "greeting": persona["greeting"],
            "catchphrase": persona["catchphrase"],
            "systemPrompt": persona["systemPrompt"],
        },
        "palette": palette,
        "accent": persona["accent"],
        "anchors": {
            "head": head_anchor,
            "headRadius": head_radius_ratio,
            "body": [0.5, 0.72],
        },
        "metrics": {
            "cutout": method,
            "heightRatio": round(height_ratio, 4),
            "style": options.style,
        },
        "frames": {"idle": "base.png"},
        "source": "photo",
    }

    buf = io.BytesIO()
    square.save(buf, format="PNG", optimize=True)
    return GeneratedPet(pack=pack, images={"base": buf.getvalue()})
