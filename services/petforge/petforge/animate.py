"""单张宠物图 -> 逐帧动画素材。

两种引擎：

- ``procedural``：纯 CPU 仿射变形（默认，零成本、零闪烁）。
- ``comfyui``：调用本机 ComfyUI 做低 denoise img2img（可选，失败自动回退）。

产物是 ``petpack`` 可直接消费的 ``animations`` 段 + 独立帧 PNG，
并可选生成一张网格图集 ``atlas.png``。
"""

from __future__ import annotations

import io
import math
from dataclasses import dataclass, field, replace
from typing import Callable

import numpy as np
from PIL import Image

from .pipeline import apply_sticker_style, remove_background

# 动作 -> 播放帧率。写进 petpack.animations[action].fps
ACTION_FPS: dict[str, float] = {
    "idle": 6,
    "walk": 8,
    "run": 10,
    "lie": 3,
    "hop": 8,
}

DEFAULT_ACTIONS: tuple[str, ...] = ("walk", "run", "lie")

# 面向观看者的动作描述，ComfyUI 用。程序化引擎只取帧数。
ACTION_PROMPTS: dict[str, str] = {
    "idle": "standing still, neutral pose, gentle breathing, front view, full body",
    "walk": "walking forward, one paw lifted, slight body bob, side step",
    "run": "running, legs stretched, body leaning forward, energetic",
    "lie": "lying down on the ground, body relaxed and flattened, head up",
    "hop": "jumping up, body stretched, paws tucked, cheerful",
}

AI_FRAME_COUNT: dict[str, int] = {"idle": 3, "walk": 4, "run": 4, "lie": 2, "hop": 3}

# 不同动作需要的重绘幅度：走路/跑步要改腿，待机只微调。
ACTION_DENOISE: dict[str, float] = {
    "idle": 0.35,
    "walk": 0.50,
    "run": 0.55,
    "lie": 0.40,
    "hop": 0.55,
}


@dataclass(frozen=True)
class Pose:
    """以脚底中心为轴心的仿射姿态。位移是画布比例。"""

    scale_x: float = 1.0
    scale_y: float = 1.0
    angle: float = 0.0
    dx: float = 0.0
    dy: float = 0.0


# 幅度刻意压小：照片宠物做大动作必然穿帮。
POSE_PLANS: dict[str, tuple[Pose, ...]] = {
    "idle": (
        Pose(1.000, 1.000, 0.0),
        Pose(0.996, 1.012, 0.25),
        Pose(0.994, 1.020, 0.50),
        Pose(0.993, 1.024, 0.70),
        Pose(0.995, 1.016, 0.45),
        Pose(0.998, 1.006, 0.20),
    ),
    "walk": (
        Pose(1.000, 1.000, 0.0),
        Pose(1.008, 0.996, 1.6, 0.004, -0.006),
        Pose(1.012, 0.992, 2.6, 0.008, -0.013),
        Pose(1.006, 0.997, 1.4, 0.004, -0.006),
        Pose(1.001, 0.999, -0.4, -0.001, -0.001),
        Pose(1.004, 1.002, -1.4, -0.004, -0.003),
    ),
    "run": (
        Pose(1.000, 1.000, 0.0),
        Pose(1.010, 0.985, 3.0, 0.008, -0.014),
        Pose(1.016, 0.972, 5.0, 0.014, -0.028),
        Pose(1.010, 0.982, 3.2, 0.008, -0.016),
        Pose(1.001, 0.998, -0.5, -0.001, -0.001),
        Pose(1.006, 1.010, -3.0, -0.008, -0.010),
    ),
    "lie": (
        Pose(1.045, 0.760, -3.0, 0.0, -0.010),
        Pose(1.048, 0.748, -3.3, 0.0, -0.008),
    ),
    "hop": (
        Pose(1.030, 0.955, 0.0, 0.0, 0.0),
        Pose(0.985, 1.060, 0.0, 0.0, -0.035),
        Pose(0.975, 1.080, 0.0, 0.0, -0.060),
        Pose(1.010, 0.985, 0.0, 0.0, -0.012),
    ),
}


@dataclass
class AnimateOptions:
    engine: str = "procedural"  # procedural | comfyui
    actions: tuple[str, ...] = DEFAULT_ACTIONS
    atlas: bool = False  # 图集较大，默认只在显式需要时生成
    frame_size: int = 512  # 导出帧边长上限，不放大
    style: str = "sticker"
    subject: str = ""  # ComfyUI 提示词里的角色描述
    outline: int = 10
    comfy: object | None = None  # comfy.ComfyOptions，延迟导入避免硬依赖
    progress: Callable[[float, str], None] | None = None

    def report(self, value: float, message: str) -> None:
        if self.progress is not None:
            self.progress(max(0.0, min(1.0, value)), message)


@dataclass
class AnimatedResult:
    images: dict[str, bytes] = field(default_factory=dict)
    animations: dict[str, dict] = field(default_factory=dict)
    atlas: dict | None = None
    engine: str = "procedural"
    fallback: str | None = None


# --------------------------------------------------------------------------- #
# 程序化帧
# --------------------------------------------------------------------------- #


def render_pose(base: Image.Image, pose: Pose, pivot_y: float = 0.985) -> Image.Image:
    """围绕脚底中心做缩放 / 旋转 / 位移，输出与 base 同尺寸的 RGBA。"""
    width, height = base.size
    pivot = np.array([width / 2.0, height * pivot_y], dtype=np.float64)

    angle = math.radians(pose.angle)
    scale = np.array([[pose.scale_x, 0.0], [0.0, pose.scale_y]], dtype=np.float64)
    rotate = np.array(
        [[math.cos(angle), -math.sin(angle)], [math.sin(angle), math.cos(angle)]],
        dtype=np.float64,
    )
    matrix = rotate @ scale
    offset = pivot + np.array([pose.dx * width, pose.dy * height], dtype=np.float64) - matrix @ pivot

    inverse = np.linalg.inv(matrix)
    shift = -inverse @ offset
    data = (
        float(inverse[0, 0]),
        float(inverse[0, 1]),
        float(shift[0]),
        float(inverse[1, 0]),
        float(inverse[1, 1]),
        float(shift[1]),
    )
    return base.transform(base.size, Image.Transform.AFFINE, data, resample=Image.Resampling.BICUBIC)


def _signature(img: Image.Image, size: int = 32) -> np.ndarray:
    """白底合成后的低分辨率灰度图，用来判断两帧是否几乎相同。"""
    background = Image.new("RGBA", img.size, (255, 255, 255, 255))
    merged = Image.alpha_composite(background, img).convert("L")
    merged = merged.resize((size, size), Image.Resampling.BILINEAR)
    return np.asarray(merged, dtype=np.float32)


def _near(a: np.ndarray, b: np.ndarray, threshold: float = 0.35) -> bool:
    return float(np.abs(a - b).mean()) < threshold


def dedupe(frames: list[Image.Image], min_keep: int = 2) -> list[Image.Image]:
    """去掉几乎相同的帧；全一样时保留差异最大的两张，避免「假动画」。"""
    if not frames:
        return []
    signatures = [_signature(frame) for frame in frames]
    kept: list[int] = []
    for index, signature in enumerate(signatures):
        if all(not _near(signature, signatures[other]) for other in kept):
            kept.append(index)

    if len(kept) < min_keep and len(frames) >= min_keep:
        best = (0, min(1, len(frames) - 1))
        best_score = -1.0
        for i in range(len(frames)):
            for j in range(i + 1, len(frames)):
                score = float(np.abs(signatures[i] - signatures[j]).mean())
                if score > best_score:
                    best, best_score = (i, j), score
        kept = list(best)

    return [frames[index] for index in kept]


def _encode_png(img: Image.Image) -> bytes:
    buffer = io.BytesIO()
    img.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


# --------------------------------------------------------------------------- #
# 对齐 / 图集
# --------------------------------------------------------------------------- #


def align_like_base(frame: Image.Image, base: Image.Image) -> Image.Image:
    """按 base 的包围盒宽度缩放、底部对齐，避免 AI 帧忽大忽小。"""
    base_box = base.getbbox()
    frame_box = frame.getbbox()
    if base_box is None or frame_box is None:
        return frame

    base_width = max(1, base_box[2] - base_box[0])
    base_bottom = base_box[3]
    base_center_x = (base_box[0] + base_box[2]) / 2.0

    cropped = frame.crop(frame_box)
    scale = base_width / max(1, cropped.width)
    # 极端比例（比如生成出了横躺）时再兜一层
    max_height = base.size[1] * 1.15
    if cropped.height * scale > max_height:
        scale = max_height / cropped.height

    new_size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    resized = cropped.resize(new_size, Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", base.size, (0, 0, 0, 0))
    left = round(base_center_x - new_size[0] / 2.0)
    top = round(base_bottom - new_size[1])
    # paste + mask 会自动裁剪越界区域，比 alpha_composite 宽容
    canvas.paste(resized, (left, top), resized)
    return canvas


def build_atlas(
    frames: list[tuple[str, Image.Image]],
    cell: int,
    columns: int,
) -> tuple[Image.Image, dict]:
    """把帧按行排进网格图集，返回 (atlas, metadata)。"""
    rows = math.ceil(len(frames) / columns) if frames else 1
    atlas = Image.new("RGBA", (cell * columns, cell * max(1, rows)), (0, 0, 0, 0))
    rects: dict[str, list[int]] = {}
    for index, (name, frame) in enumerate(frames):
        column = index % columns
        row = index // columns
        atlas.alpha_composite(frame, (column * cell, row * cell))
        rects[name] = [column * cell, row * cell, cell, cell]
    return atlas, {"cell": cell, "columns": columns, "rows": max(1, rows), "frames": rects}


# --------------------------------------------------------------------------- #
# 引擎
# --------------------------------------------------------------------------- #


def _procedural_frames(base: Image.Image, actions: tuple[str, ...]) -> list[tuple[str, str, Image.Image]]:
    frames: list[tuple[str, str, Image.Image]] = []
    for action in actions:
        plan = POSE_PLANS.get(action)
        if not plan:
            continue
        rendered = [render_pose(base, pose) for pose in plan]
        for index, frame in enumerate(dedupe(rendered)):
            frames.append((action, f"{action}_{index}", frame))
    return frames


def _ai_frames(
    base: Image.Image,
    base_png: bytes,
    actions: tuple[str, ...],
    options: AnimateOptions,
) -> list[tuple[str, str, Image.Image]]:
    from . import comfy

    comfy_options = options.comfy or comfy.ComfyOptions()
    if not comfy.is_available(comfy_options.host):
        raise comfy.ComfyError(f"ComfyUI 不可达：{comfy_options.host}")

    # ComfyUI 的 LoadImage 会丢掉 alpha；先垫白底，rembg 也更容易把主体切出来。
    flat = Image.new("RGB", base.size, (255, 255, 255))
    flat.paste(base, mask=base.getchannel("A"))
    base_png = _encode_png(flat)

    frames: list[tuple[str, str, Image.Image]] = []
    total = sum(AI_FRAME_COUNT.get(action, 3) for action in actions)
    done = 0
    subject = options.subject.strip()
    for action in actions:
        count = AI_FRAME_COUNT.get(action, 3)
        for index in range(count):
            action_prompt = ACTION_PROMPTS.get(action, action)
            prompt = f"{subject}, {action_prompt}, {comfy.BASE_PROMPT}" if subject else f"{comfy.BASE_PROMPT}, {action_prompt}"
            frame_options = replace(
                comfy_options,
                denoise=ACTION_DENOISE.get(action, comfy_options.denoise),
            )
            data = comfy.generate_frame(
                base_png,
                prompt=prompt,
                seed=20261101 + index * 37 + len(frames) * 101,
                options=frame_options,
            )
            image = Image.open(io.BytesIO(data)).convert("RGBA")
            cut, _method = remove_background(image)
            aligned = align_like_base(cut, base)
            if options.style == "sticker":
                aligned = apply_sticker_style(aligned, outline_px=options.outline)
            frames.append((action, f"{action}_{index}", aligned))
            done += 1
            options.report(done / max(1, total), f"ComfyUI 生成 {action} {index + 1}/{count}")
    return frames


def generate_animation(
    base_image: Image.Image | bytes,
    options: AnimateOptions | None = None,
) -> AnimatedResult:
    """给已抠好的宠物图生成动作帧与 petpack.animations。"""
    options = options or AnimateOptions()
    base = (
        Image.open(io.BytesIO(base_image)).convert("RGBA")
        if isinstance(base_image, bytes)
        else base_image.convert("RGBA")
    )
    actions = tuple(action for action in options.actions if action in ACTION_FPS)
    if not actions:
        return AnimatedResult(engine=options.engine)

    fallback: str | None = None
    engine = options.engine if options.engine in {"procedural", "comfyui"} else "procedural"
    if engine == "comfyui":
        try:
            options.report(0.05, "连接 ComfyUI…")
            frames = _ai_frames(base, _encode_png(base), actions, options)
        except Exception as error:  # noqa: BLE001 - 任何失败都降级，不能阻断生成
            fallback = f"{type(error).__name__}: {error}"
            frames = _procedural_frames(base, actions)
            options.report(0.6, "ComfyUI 不可用，已回退程序化动画")
    else:
        frames = _procedural_frames(base, actions)

    # 桌面宠物实际显示尺寸只有一两百像素，512 足够；再大只是白送带宽。
    target = min(options.frame_size, base.size[0])
    if target and target != base.size[0]:
        frames = [
            (action, name, frame.resize((target, target), Image.Resampling.LANCZOS))
            for action, name, frame in frames
        ]

    images: dict[str, bytes] = {}
    animations: dict[str, dict] = {}
    for action in actions:
        action_frames = [(name, frame) for act, name, frame in frames if act == action]
        if not action_frames:
            continue
        if len(action_frames) < 2:  # 单帧不值得做 flipbook
            continue
        animations[action] = {
            "fps": ACTION_FPS[action],
            "frames": [f"{name}.png" for name, _frame in action_frames],
        }
        for name, frame in action_frames:
            images[name] = _encode_png(frame)

    atlas_meta: dict | None = None
    if options.atlas and animations:
        animated_names = {file[:-4] for data in animations.values() for file in data["frames"]}
        ordered = [(name, frame) for _act, name, frame in frames if name in animated_names]
        columns = max(len(data["frames"]) for data in animations.values())
        cell = ordered[0][1].size[0] if ordered else base.size[0]
        atlas, meta = build_atlas(ordered, cell, columns)
        atlas_meta = {"file": "atlas.png", **meta}
        images["atlas"] = _encode_png(atlas)

    return AnimatedResult(
        images=images,
        animations=animations,
        atlas=atlas_meta,
        engine="procedural" if fallback else engine,
        fallback=fallback,
    )


def write_pack_animation(pack: dict, result: AnimatedResult) -> dict:
    """把动画结果合并进 petpack（原地修改并返回）。"""
    if result.animations:
        pack["animations"] = result.animations
    if result.atlas:
        pack["atlas"] = result.atlas
    metrics = pack.setdefault("metrics", {})
    metrics["animate"] = result.engine
    if result.fallback:
        metrics["animateFallback"] = result.fallback
    return pack
