"""生成 App 内置宠物（橘猫 / 薄荷猫 / 芋泥兔）的 6 种表情帧。

    python tools/make_builtin_pets.py

产物（供 Flutter 直接作为 assets 使用）:
    app/assets/pets/<id>/idle.png, happy.png, love.png, angry.png, sleepy.png, blink.png
    app/assets/pets/<id>/petpack.json

应用图标已独立为「有财」形象，由 tools/make_youcai_icons.py 生成并维护；
本脚本不再写 app/assets/icons/，避免重跑时把托盘 / 任务栏图标改回内置宠物。
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "services" / "petforge"))

from petforge.pipeline import apply_sticker_style  # noqa: E402

OUT = ROOT / "app" / "assets"
BASE = 512
SS = 4  # 超采样倍数
S = BASE * SS

PETS = {
    "doudou": {
        "kind": "dog",
        "name": "小黄豆",
        "body": "#F2B65A",
        "shade": "#D9922F",
        "belly": "#FFF9EC",
        "inner": "#FFD79A",
        "palette": ["#F2B65A", "#FFF9EC", "#D9922F", "#FFD79A", "#4A352E"],
        "traits": ["憨厚", "黏人", "摇尾巴"],
        "greeting": "汪！主人回来啦，我尾巴都要摇断了。",
    },
    "momo": {
        "kind": "cat",
        "name": "橘子团子",
        "body": "#F7AA5F",
        "shade": "#E6873D",
        "belly": "#FFE3C2",
        "inner": "#FFB9A8",
        "palette": ["#F7AA5F", "#FFE3C2", "#E6873D", "#FFB9A8", "#5A4034"],
        "traits": ["元气", "贪吃", "黏人"],
        "greeting": "嗨，我是橘子团子！今天有带小零食吗？",
    },
    "mint": {
        "kind": "cat",
        "name": "薄荷麻薯",
        "body": "#8FD8C6",
        "shade": "#5FB9A6",
        "belly": "#EAFFF9",
        "inner": "#B7EADF",
        "palette": ["#8FD8C6", "#EAFFF9", "#5FB9A6", "#B7EADF", "#3E4B48"],
        "traits": ["安静", "温柔", "好奇心重"],
        "greeting": "……你好呀。要一起晒太阳吗？",
    },
    "taro": {
        "kind": "bunny",
        "name": "芋泥汤圆",
        "body": "#BBA8EC",
        "shade": "#9985D2",
        "belly": "#F2EBFF",
        "inner": "#DCCBFF",
        "palette": ["#BBA8EC", "#F2EBFF", "#9985D2", "#DCCBFF", "#4A4058"],
        "traits": ["害羞", "爱撒娇", "慢热"],
        "greeting": "诶…你、你看到我了吗？我是芋泥汤圆…",
    },
}

FRAMES = ["idle", "happy", "love", "angry", "sleepy", "blink"]
INK = "#4A352E"


def u(value: float) -> int:
    """把 512 坐标系换算到超采样坐标系。"""
    return int(round(value * SS))


def hex_rgb(color: str) -> tuple[int, int, int]:
    color = color.lstrip("#")
    return tuple(int(color[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def gradient(size: int, top: str, bottom: str) -> Image.Image:
    t = np.array(hex_rgb(top), dtype=np.float32)
    b = np.array(hex_rgb(bottom), dtype=np.float32)
    ramp = np.linspace(0, 1, size, dtype=np.float32)[:, None, None]
    arr = (t[None, None, :] * (1 - ramp) + b[None, None, :] * ramp)
    arr = np.repeat(arr, size, axis=1).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def rounded_shape(points: list[tuple[float, float]], radius: float = 26) -> Image.Image:
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon([(u(x), u(y)) for x, y in points], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius * SS * 0.45))
    return mask.point(lambda v: 255 if v > 128 else 0)


def paste_mask(canvas: Image.Image, mask: Image.Image, fill: Image.Image | str, alpha: int = 255) -> None:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if isinstance(fill, str):
        layer.paste(Image.new("RGBA", (S, S), hex_rgb(fill) + (alpha,)), (0, 0), mask)
    else:
        layer.paste(fill.convert("RGBA"), (0, 0), mask)
    canvas.alpha_composite(layer)


def rotated_ellipse(size: tuple[float, float], center: tuple[float, float], angle: float,
                    fill: tuple[int, ...]) -> Image.Image:
    """画一个旋转椭圆，返回整幅画布大小的图层，方便直接 alpha_composite。"""
    w, h = int(size[0] * SS), int(size[1] * SS)
    patch = Image.new("RGBA", (max(w, 2), max(h, 2)), (0, 0, 0, 0))
    ImageDraw.Draw(patch).ellipse([0, 0, w - 1, h - 1], fill=fill)
    patch = patch.rotate(angle, expand=True, resample=Image.BICUBIC)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.alpha_composite(patch, (u(center[0]) - patch.width // 2, u(center[1]) - patch.height // 2))
    return canvas


def draw_body(kind: str, pose: str = "idle", phase: float = 0.0) -> Image.Image:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    if kind == "dog":
        ears = []
    elif kind == "cat":
        ears = [
            [(138, 205), (118, 78), (218, 150)],
            [(374, 205), (394, 78), (294, 150)],
        ]
    else:
        ears = [
            [(168, 200), (150, 52), (238, 148)],
            [(344, 200), (362, 52), (274, 148)],
        ]
    # ---- 动作姿态：腿 / 尾巴 / 耳朵 / 身体逐帧变化（walk、run 由 phase 驱动） ----
    t = phase * math.tau
    body_dy = 0.0
    body_dx = 0.0
    foot_dy = [0.0, 0.0]
    foot_dx = [0.0, 0.0]
    tail_dy = 0.0
    ear_dy = 0.0
    lie = pose.startswith("lie")
    if pose.startswith("walk"):
        body_dy = -5.0 * abs(math.sin(t))
        foot_dy = [-15.0 * max(0.0, math.sin(t)), -15.0 * max(0.0, math.sin(t + math.pi))]
        foot_dx = [9.0 * math.sin(t), -9.0 * math.sin(t)]
        tail_dy = 7.0 * math.sin(t)
        ear_dy = -3.0 * abs(math.sin(t))
    elif pose.startswith("run"):
        body_dy = -11.0 * abs(math.sin(t))
        body_dx = -7.0
        foot_dy = [-24.0 * max(0.0, math.sin(t)), -24.0 * max(0.0, math.sin(t + math.pi))]
        foot_dx = [16.0 * math.sin(t), -16.0 * math.sin(t)]
        tail_dy = -12.0
        ear_dy = -7.0 * abs(math.sin(t))
    elif pose.startswith("hop"):
        # 开心跳起：身体弹起离地、四肢收起、耳朵尾巴上扬
        lift = abs(math.sin(t))
        body_dy = -38.0 * lift
        foot_dy = [-20.0 * lift, -20.0 * lift]
        foot_dx = [12.0 * math.sin(t), -12.0 * math.sin(t)]
        tail_dy = -16.0 * lift
        ear_dy = -9.0 * lift
    elif pose.startswith("sad"):
        # 委屈落地：趴低、脚向两侧岔开、耳朵尾巴耷拉
        body_dy = 24.0 + 2.0 * math.sin(t)
        foot_dx = [-30.0, 30.0]
        foot_dy = [12.0, 12.0]
        tail_dy = 26.0
        ear_dy = 6.0
    elif lie:
        # 趴下：身体摊开下沉、脚向两侧岔开、尾巴搭在一边，phase 驱动呼吸起伏
        body_dy = 30.0 + 3.0 * math.sin(t)
        foot_dx = [-52.0, 52.0]
        foot_dy = [18.0, 18.0]
        tail_dy = 22.0
        ear_dy = 10.0
    ears = [[(x, y + ear_dy + body_dy * 0.3) for x, y in tri] for tri in ears]
    for ear in ears:
        mask = rounded_shape(ear, radius=24)
        paste_mask(layer, mask, WORLD_COLORS["body"])
        inner = [(ear[0][0] * 0.82 + ear[1][0] * 0.18, ear[0][1] * 0.82 + ear[1][1] * 0.18),
                 (ear[0][0] * 0.55 + ear[1][0] * 0.45, ear[0][1] * 0.55 + ear[1][1] * 0.45),
                 (ear[0][0] * 0.5 + ear[2][0] * 0.5, ear[0][1] * 0.5 + ear[2][1] * 0.5)]
        paste_mask(layer, rounded_shape(inner, radius=16), WORLD_COLORS["inner"], alpha=150)

    # 尾巴 / 兔子的短尾
    tail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tail)
    if kind == "dog":
        curve = [(x, y + tail_dy) for x, y in [(356, 414), (408, 406), (438, 380), (444, 350)]]
        path = [(u(x), u(y)) for x, y in curve]
        td.line(path, fill=hex_rgb(WORLD_COLORS["body"]) + (255,), width=u(36), joint="curve")
        for x, y in path[:-1]:
            td.ellipse([x - u(18), y - u(18), x + u(18), y + u(18)], fill=hex_rgb(WORLD_COLORS["body"]) + (255,))
        # 尾巴尖是白的
        td.line([path[-2], path[-1]], fill=hex_rgb(WORLD_COLORS["belly"]) + (255,), width=u(36))
        for x, y in (path[-2], path[-1]):
            td.ellipse([x - u(18), y - u(18), x + u(18), y + u(18)],
                       fill=hex_rgb(WORLD_COLORS["belly"]) + (255,))
    elif kind == "cat":
        curve = [(x, y + tail_dy) for x, y in [(356, 436), (412, 430), (448, 396), (452, 352), (436, 322)]]
        path = [(u(x), u(y)) for x, y in curve]
        td.line(path, fill=hex_rgb(WORLD_COLORS["body"]) + (255,), width=u(30), joint="curve")
        for x, y in (path[0], path[1], path[-1]):
            td.ellipse([x - u(15), y - u(15), x + u(15), y + u(15)], fill=hex_rgb(WORLD_COLORS["body"]) + (255,))
    else:
        td.ellipse([u(352), u(352 + tail_dy), u(430), u(430 + tail_dy)], fill=hex_rgb(WORLD_COLORS["belly"]) + (255,))
    layer.alpha_composite(tail)

    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    if lie:
        body_box = [86, 190 + body_dy, 438, 428 + body_dy]
        body_radius = 110
    else:
        body_box = [108 + body_dx, 150 + body_dy, 404 + body_dx, 452 + body_dy]
        body_radius = 140
    bd.rounded_rectangle(
        [u(v) for v in body_box],
        radius=u(body_radius),
        fill=hex_rgb(WORLD_COLORS["body"]) + (255,),
    )
    body = body.filter(ImageFilter.GaussianBlur(SS * 1.2))
    # 用渐变重新上色，保留 alpha
    grad = gradient(S, WORLD_COLORS["body"], WORLD_COLORS["shade"]).convert("RGBA")
    grad.putalpha(body.getchannel("A"))
    layer.alpha_composite(grad)

    # 肚皮
    belly = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    belly_box = [170, 300 + body_dy, 350, 408 + body_dy] if lie else [186 + body_dx, 290 + body_dy, 326 + body_dx, 432 + body_dy]
    ImageDraw.Draw(belly).ellipse([u(v) for v in belly_box], fill=hex_rgb(WORLD_COLORS["belly"]) + (235,))
    belly = belly.filter(ImageFilter.GaussianBlur(SS * 2))
    layer.alpha_composite(belly)

    # 脚
    feet = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fd = ImageDraw.Draw(feet)
    for i, cx in enumerate((198, 314)):
        fx = cx + body_dx * 0.6 + foot_dx[i]
        fy = 390 + body_dy * 0.5 + foot_dy[i]
        fd.ellipse([u(fx - 48), u(fy), u(fx + 48), u(fy + 56)], fill=hex_rgb(WORLD_COLORS["body"]) + (255,))
    feet = feet.filter(ImageFilter.GaussianBlur(SS * 1.0))
    layer.alpha_composite(feet)

    # 垂耳：盖在脑袋两侧，向外耷拉（画在身体之后，形状才看得出来）
    if kind == "dog":
        for side in (-1, 1):
            ear = rotated_ellipse(
                (88, 180),
                (256 + side * 148, 316 + ear_dy + body_dy * 0.4),
                side * 12,
                hex_rgb(WORLD_COLORS["body"]) + (255,),
            )
            layer.alpha_composite(ear)
            shadow = rotated_ellipse(
                (58, 120),
                (256 + side * 150, 356 + ear_dy + body_dy * 0.4),
                side * 12,
                hex_rgb(WORLD_COLORS["shade"]) + (70,),
            )
            layer.alpha_composite(shadow)

    # 白面：额头白斑 + 白色口鼻（黄狗白面的关键特征）
    if kind == "dog":
        white = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        wd = ImageDraw.Draw(white)
        fy = body_dy * 0.8
        wd.ellipse([u(214 + body_dx), u(204 + fy), u(298 + body_dx), u(310 + fy)], fill=hex_rgb(WORLD_COLORS["belly"]) + (255,))
        wd.ellipse([u(164 + body_dx), u(284 + fy), u(348 + body_dx), u(380 + fy)], fill=hex_rgb(WORLD_COLORS["belly"]) + (255,))
        white = white.filter(ImageFilter.GaussianBlur(SS * 5.5))
        layer.alpha_composite(white)

    # 顶部高光
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse([u(172 + body_dx), u(186 + body_dy), u(286 + body_dx), u(232 + body_dy)], fill=(255, 255, 255, 26))
    shine = shine.filter(ImageFilter.GaussianBlur(SS * 9))
    layer.alpha_composite(shine)
    return layer


def eye_open(d: ImageDraw.ImageDraw, cx: float, cy: float, rx: float = 25, ry: float = 29) -> None:
    d.ellipse([u(cx - rx), u(cy - ry), u(cx + rx), u(cy + ry)], fill=hex_rgb(INK) + (255,))
    d.ellipse([u(cx - 15), u(cy - 20), u(cx - 1), u(cy - 6)], fill=(255, 255, 255, 255))


def eye_arc(d: ImageDraw.ImageDraw, cx: float, cy: float, up: bool = True, width: float = 8) -> None:
    box = [u(cx - 26), u(cy - 18), u(cx + 26), u(cy + 18)]
    start, end = (180, 360) if up else (0, 180)
    d.arc(box, start=start, end=end, fill=hex_rgb(INK) + (255,), width=u(width))


def eye_heart(d: ImageDraw.ImageDraw, cx: float, cy: float, size: float = 22) -> None:
    r = size * 0.62
    d.ellipse([u(cx - size), u(cy - r), u(cx), u(cy + r * 0.35)], fill=hex_rgb("#FF5F7A") + (255,))
    d.ellipse([u(cx), u(cy - r), u(cx + size), u(cy + r * 0.35)], fill=hex_rgb("#FF5F7A") + (255,))
    d.polygon([(u(cx - size), u(cy + r * 0.1)), (u(cx + size), u(cy + r * 0.1)), (u(cx), u(cy + size * 1.15))],
              fill=hex_rgb("#FF5F7A") + (255,))


def draw_face(expr: str) -> Image.Image:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # 腮红
    if expr in {"happy", "love", "sleepy"}:
        for cx in (163, 349):
            blush = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            ImageDraw.Draw(blush).ellipse([u(cx - 30), u(300), u(cx + 30), u(332)], fill=(255, 128, 150, 120))
            layer.alpha_composite(blush.filter(ImageFilter.GaussianBlur(SS * 3)))

    if expr in {"idle", "happy", "love", "angry"}:
        for cx in (200, 312):
            if expr == "happy":
                eye_arc(d, cx, 262, up=True, width=9)
            elif expr == "love":
                eye_heart(d, cx, 262, size=21)
            elif expr == "angry":
                # 眯眼 + 压低的眉毛
                eye_arc(d, cx, 266, up=True, width=8)
                d.line([u(cx - 24), u(232), u(cx + 24), u(244)], fill=hex_rgb(INK) + (255,), width=u(8))
            else:
                eye_open(d, cx, 262)
    else:  # sleepy / blink
        for cx in (200, 312):
            eye_arc(d, cx, 262, up=False, width=7)

    # 狗鼻子 + 鼻子到嘴的连接线
    if WORLD_KIND == "dog":
        d.ellipse([u(237), u(294), u(275), u(320)], fill=hex_rgb(INK) + (255,))
        d.polygon([(u(244), u(314)), (u(268), u(314)), (u(256), u(324))], fill=hex_rgb(INK) + (255,))
        for side in (-1, 1):
            d.arc([u(256 + side * 16 - 13), u(322), u(256 + side * 16 + 13), u(340)],
                  start=195 if side < 0 else 345, end=345 if side < 0 else 495,
                  fill=hex_rgb(INK) + (235,), width=u(4))

    # 嘴
    if expr in {"happy", "love"}:
        d.ellipse([u(238), u(302), u(276), u(334)], fill=hex_rgb(INK) + (255,))
        d.ellipse([u(246), u(320), u(268), u(333)], fill=hex_rgb("#FF8A9A") + (255,))
    elif expr == "angry":
        d.arc([u(228), u(318), u(284), u(352)], start=200, end=340, fill=hex_rgb(INK) + (255,), width=u(7))
    elif expr == "sleepy":
        d.ellipse([u(248), u(318), u(266), u(334)], fill=hex_rgb(INK) + (230,))
    else:
        for cx in (244, 268):
            d.arc([u(cx - 12), u(306), u(cx + 12), u(326)], start=0, end=180, fill=hex_rgb(INK) + (255,), width=u(6))

    # 猫须
    if WORLD_KIND == "cat":
        for side in (-1, 1):
            for dy, length in ((0, 30), (16, 26)):
                x1 = 256 + side * 112
                d.line([u(x1), u(336 + dy), u(x1 + side * length), u(330 + dy)], fill=hex_rgb(INK) + (80,), width=u(3))

    if WORLD_KIND == "dog" and expr in {"happy", "love"}:
        d.rounded_rectangle([u(240), u(330), u(272), u(362)], radius=u(14), fill=hex_rgb("#FF8F9E") + (255,))

    if WORLD_KIND == "dog":
        for cx in (200, 312):
            d.ellipse([u(cx - 9), u(206), u(cx + 9), u(224)], fill=hex_rgb(WORLD_COLORS["belly"]) + (210,))

    if expr == "angry":
        for i, (x, y) in enumerate(((378, 150), (396, 132))):
            d.line([u(x - 22), u(y + 8), u(x + 14), u(y - 12)], fill=hex_rgb("#F2544B") + (255,), width=u(9))
            d.line([u(x - 6), u(y - 26), u(x + 12), u(y + 8)], fill=hex_rgb("#F2544B") + (255,), width=u(9))

    return layer


WORLD_COLORS: dict[str, str] = {}
WORLD_KIND = "cat"


def render(kind: str, colors: dict[str, str], expr: str, pose: str = "idle", phase: float = 0.0) -> Image.Image:
    global WORLD_COLORS, WORLD_KIND
    WORLD_COLORS, WORLD_KIND = colors, kind
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas.alpha_composite(draw_body(kind, pose, phase))
    face = draw_face(expr)
    if pose.startswith("lie"):
        # 趴下时脑袋歪向一边撒娇
        face = face.rotate(-15, resample=Image.BICUBIC, center=(S // 2, int(S * 0.42)))
    canvas.alpha_composite(face)
    small = canvas.resize((BASE, BASE), Image.LANCZOS)
    return apply_sticker_style(small, outline_px=9)


def main() -> int:
    for pet_id, spec in PETS.items():
        folder = OUT / "pets" / pet_id
        folder.mkdir(parents=True, exist_ok=True)
        for expr in FRAMES:
            image = render(spec["kind"], spec, expr)
            image.save(folder / f"{expr}.png", optimize=True)
        # 动作帧动画：walk / run / lie 各自的逐帧序列
        anim_specs = {
            "walk": ([("walk_0", 0.0), ("walk_1", 0.25), ("walk_2", 0.5), ("walk_3", 0.75)], "idle", "walk", 8),
            "run": ([("run_0", 0.0), ("run_1", 0.25), ("run_2", 0.5), ("run_3", 0.75)], "happy", "run", 12),
            "lie": ([("lie_0", 0.0), ("lie_1", 0.5)], "love", "lie", 2.5),
            "hop": ([("hop_0", 0.0), ("hop_1", 0.25), ("hop_2", 0.5), ("hop_3", 0.75)], "happy", "hop", 12),
            "drop": ([("drop_0", 0.0), ("drop_1", 0.5)], "sleepy", "sad", 3),
        }
        animations = {}
        for anim_name, (anim_frames, anim_expr, anim_pose, anim_fps) in anim_specs.items():
            files = []
            for frame_name, frame_phase in anim_frames:
                image = render(spec["kind"], spec, anim_expr, pose=anim_pose, phase=frame_phase)
                image.save(folder / f"{frame_name}.png", optimize=True)
                files.append(f"{frame_name}.png")
            animations[anim_name] = {"fps": anim_fps, "frames": files}

        pack = {
            "schemaVersion": 1,
            "name": spec["name"],
            "personality": {
                "traits": spec["traits"],
                "tone": "短句、口语化、偶尔用颜文字，每次不超过 40 字",
                "greeting": spec["greeting"],
                "catchphrase": spec["greeting"],
                "systemPrompt": (
                    f"你是一只名叫「{spec['name']}」的桌面宠物。\n"
                    f"你的性格：{'、'.join(spec['traits'])}。\n"
                    "说话短句、口语化、偶尔用颜文字，每次不超过 40 字，称呼主人为「主人」。\n"
                    "永远保持角色，不要提及自己是 AI。回答格式：[情绪]正文，"
                    "情绪只能是 happy / love / angry / sleepy / idle 之一。"
                ),
            },
            "palette": spec["palette"],
            "accent": spec["palette"][0],
            "anchors": {"head": [0.5, 0.34], "headRadius": 0.27, "body": [0.5, 0.72]},
            "metrics": {"cutout": "drawn", "heightRatio": 0.78, "style": "sticker"},
            "frames": {expr: f"{expr}.png" for expr in FRAMES},
            "animations": animations,
            "source": "builtin",
        }
        (folder / "petpack.json").write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[ok] {pet_id} -> {folder}")

    # 应用图标不在这里生成：托盘 / 任务栏 / EXE 图标统一由 make_youcai_icons.py
    # 以 exports/有财/base.png 为母版输出，重跑本脚本不会覆盖它们。
    print("[skip] icons -> 由 tools/make_youcai_icons.py 维护（有财）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
