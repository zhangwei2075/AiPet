"""从主色调推导宠物名字、性格与提示词。

全部由输入图片的哈希决定：同一张照片永远得到同一只宠物，
方便用户重新生成 / 跨设备复现。
"""

from __future__ import annotations

import colorsys
import hashlib
from typing import Any


def _hsv(hex_color: str) -> tuple[float, float, float]:
    hex_color = hex_color.lstrip("#")
    r, g, b = (int(hex_color[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hsv(r, g, b)


def _seed_of(palette: list[str]) -> int:
    raw = "|".join(palette).encode("utf-8")
    return int(hashlib.sha1(raw).hexdigest()[:8], 16)


# 按色相分组的命名库：名字 + 后缀
_NAME_POOLS: list[tuple[float, float, list[str]]] = [
    (0, 22, ["橘子", "焦糖", "柿子", "小橘", "枫糖", "暖阳"]),
    (22, 45, ["布丁", "奶黄", "蜂蜜", "蛋黄", "南瓜", "芝士"]),
    (45, 80, ["抹茶", "青柠", "豌豆", "柚子", "嫩芽"]),
    (80, 160, ["薄荷", "海盐", "青提", "翡翠", "雪碧"]),
    (160, 200, ["湖水", "蓝莓", "汽水", "冰川", "小鱼"]),
    (200, 250, ["蓝调", "夜空", "海豚", "墨水", "星尘"]),
    (250, 290, ["芋泥", "葡萄", "紫薯", "梦境", "紫菜"]),
    (290, 330, ["桃桃", "草莓", "樱花", "玫瑰", "泡泡"]),
    (330, 361, ["莓莓", "西瓜", "火苗", "山楂", "小莓"]),
]

_SUFFIXES = ["团子", "布丁", "年糕", "麻薯", "豆豆", "小卷", "汤圆", "软糖"]

_TRAIT_POOLS = {
    "warm": ["元气", "黏人", "贪吃", "爱撒娇"],
    "cool": ["安静", "有点高冷", "好奇心重", "慢热"],
    "green": ["佛系", "温柔", "喜欢晒太阳", "慢性子"],
    "pink": ["害羞", "爱漂亮", "容易脸红", "甜"],
}

_CATCHPHRASES = {
    "warm": ["今天也要开心呀！", "有你在真好～", "肚子饿了…"],
    "cool": ["……嗯。", "别打扰我发呆。", "你来了。"],
    "green": ["慢慢来就好。", "晒晒太阳吧。", "呼——"],
    "pink": ["诶…被看到了。", "要摸摸头吗？", "嘿嘿。"],
}


def _bucket(hue_deg: float) -> str:
    if 330 <= hue_deg or hue_deg < 25:
        return "warm"
    if 25 <= hue_deg < 75:
        return "warm"
    if 75 <= hue_deg < 165:
        return "green"
    if 165 <= hue_deg < 265:
        return "cool"
    return "pink"


def build_persona(palette: list[str]) -> dict[str, Any]:
    """根据调色板生成 {name, traits, tone, greeting, catchphrase, systemPrompt}。"""
    seed = _seed_of(palette)
    dominant = palette[0] if palette else "#f6b26b"
    h, s, v = _hsv(dominant)

    # 低饱和度的照片（黑白/灰）按暖色处理，避免名字过于奇怪
    if s < 0.12:
        h = 32.0
    hue_deg = h * 360

    pool = next((names for lo, hi, names in _NAME_POOLS if lo <= hue_deg < hi), _NAME_POOLS[1][2])
    suffix = _SUFFIXES[seed % len(_SUFFIXES)]
    name = f"{pool[(seed >> 3) % len(pool)]}{suffix}"

    bucket = _bucket(hue_deg)
    traits = _TRAIT_POOLS[bucket][:]
    # 用哈希做一次确定性轮换，让同色系的宠物也有差异
    shift = (seed >> 7) % len(traits)
    traits = traits[shift:] + traits[:shift]
    traits = traits[:3]

    catchphrase = _CATCHPHRASES[bucket][seed % len(_CATCHPHRASES[bucket])]
    tone = "短句、口语化、偶尔用颜文字，不要长篇大论（每次不超过 40 字）"
    greeting = f"嗨，我是{name}！{catchphrase}"

    system_prompt = (
        f"你是一只名叫「{name}」的桌面宠物，外形来自主人的照片。\n"
        f"你的性格：{'、'.join(traits)}。\n"
        f"说话风格：{tone}。\n"
        f"称呼主人为「主人」。永远保持角色，不要提及自己是 AI 或模型。\n"
        f"如果主人问你不会的事，就卖萌带过。回答时先输出一个情绪标签，"
        f"格式：[情绪]正文，情绪只能是 happy / love / angry / sleepy / idle 之一。\n"
        f"例：[happy]主人回来啦，我等你好久了！"
    )

    return {
        "name": name,
        "traits": traits,
        "tone": tone,
        "greeting": greeting,
        "catchphrase": catchphrase,
        "systemPrompt": system_prompt,
        "accent": palette[0] if palette else "#f6b26b",
    }
