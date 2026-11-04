import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 本地生成（无法连接 PetForge 时）用到的命名 / 性格逻辑，
/// 与 services/petforge/petforge/persona.py 保持一致的口味。
class LocalPersona {
  const LocalPersona({
    required this.name,
    required this.traits,
    required this.greeting,
    required this.systemPrompt,
  });

  final String name;
  final List<String> traits;
  final String greeting;
  final String systemPrompt;
}

const _pools = <List<Object>>[
  [0.0, 22.0, ['橘子', '焦糖', '柿子', '小橘', '枫糖', '暖阳']],
  [22.0, 45.0, ['布丁', '奶黄', '蜂蜜', '蛋黄', '南瓜', '芝士']],
  [45.0, 80.0, ['抹茶', '青柠', '豌豆', '柚子', '嫩芽']],
  [80.0, 160.0, ['薄荷', '海盐', '青提', '翡翠', '雪碧']],
  [160.0, 200.0, ['湖水', '蓝莓', '汽水', '冰川', '小鱼']],
  [200.0, 250.0, ['蓝调', '夜空', '海豚', '墨水', '星尘']],
  [250.0, 290.0, ['芋泥', '葡萄', '紫薯', '梦境', '紫菜']],
  [290.0, 330.0, ['桃桃', '草莓', '樱花', '玫瑰', '泡泡']],
  [330.0, 361.0, ['莓莓', '西瓜', '火苗', '山楂', '小莓']],
];

const _suffixes = ['团子', '布丁', '年糕', '麻薯', '豆豆', '小卷', '汤圆', '软糖'];

enum _Bucket { warm, green, cool, pink }

LocalPersona buildLocalPersona(Color accent) {
  final hsv = HSVColor.fromColor(accent);
  var hue = hsv.hue;
  if (hsv.saturation < 0.12) hue = 32;
  final seed = accent.toARGB32() ^ 0x5f3759df;

  final pool = _pools.firstWhere(
    (entry) => hue >= (entry[0] as double) && hue < (entry[1] as double),
    orElse: () => _pools[1],
  );
  final words = (pool[2] as List).cast<String>();
  final name = '${words[seed % words.length]}${_suffixes[(seed >> 3) % _suffixes.length]}';

  final _Bucket bucket;
  if (hue < 75 || hue >= 330) {
    bucket = _Bucket.warm;
  } else if (hue < 165) {
    bucket = _Bucket.green;
  } else if (hue < 265) {
    bucket = _Bucket.cool;
  } else {
    bucket = _Bucket.pink;
  }

  final traits = switch (bucket) {
    _Bucket.warm => ['元气', '黏人', '贪吃'],
    _Bucket.green => ['佛系', '温柔', '慢性子'],
    _Bucket.cool => ['安静', '慢热', '好奇心重'],
    _Bucket.pink => ['害羞', '爱撒娇', '甜'],
  };

  return LocalPersona(
    name: name,
    traits: traits,
    greeting: '嗨，我是$name！以后就住在你的桌面啦。',
    systemPrompt:
        '你是一只名叫「$name」的桌面宠物，外形来自主人的照片。\n'
        '你的性格：${traits.join('、')}。\n'
        '说话短句、口语化、偶尔用颜文字，每次不超过 40 字，称呼主人为「主人」。\n'
        '永远保持角色，不要提及自己是 AI。回答格式：[情绪]正文，'
        '情绪只能是 happy / love / angry / sleepy / idle 之一。',
  );
}

/// 简单的字符串稳定哈希，保证同一张照片得到同一个名字。
int stableHash(String input) {
  var hash = 2166136261;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return math.max(1, hash);
}
