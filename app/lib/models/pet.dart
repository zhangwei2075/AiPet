import 'dart:io';

import 'package:flutter/material.dart';

/// 宠物表情。照片生成的宠物通常只有 [idle] 一帧，
/// 其余表情由动画引擎（挤压 / 摆动 / 粒子）叠加表现。
enum PetMood { idle, happy, love, angry, sleepy, blink, talk }

extension PetMoodParsing on PetMood {
  static PetMood fromKey(String? key) {
    for (final mood in PetMood.values) {
      if (mood.name == key) return mood;
    }
    return PetMood.idle;
  }
}

@immutable
class PetAnchors {
  const PetAnchors({
    this.head = const Offset(0.5, 0.26),
    this.headRadius = 0.26,
    this.body = const Offset(0.5, 0.72),
  });

  final Offset head;
  final double headRadius;
  final Offset body;

  factory PetAnchors.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PetAnchors();
    List<double> pair(dynamic value, List<double> fallback) {
      if (value is List && value.length >= 2) {
        return [((value[0] as num).toDouble()), ((value[1] as num).toDouble())];
      }
      return fallback;
    }

    final head = pair(json['head'], const [0.5, 0.26]);
    final body = pair(json['body'], const [0.5, 0.72]);
    return PetAnchors(
      head: Offset(head[0], head[1]),
      headRadius: (json['headRadius'] as num?)?.toDouble() ?? 0.26,
      body: Offset(body[0], body[1]),
    );
  }
}

@immutable
class PetPersonality {
  const PetPersonality({
    required this.traits,
    required this.tone,
    required this.greeting,
    required this.catchphrase,
    required this.systemPrompt,
  });

  final List<String> traits;
  final String tone;
  final String greeting;
  final String catchphrase;
  final String systemPrompt;

  factory PetPersonality.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    final traits = (data['traits'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return PetPersonality(
      traits: traits,
      tone: data['tone']?.toString() ?? '短句、可爱',
      greeting: data['greeting']?.toString() ?? '嗨，我在这里！',
      catchphrase: data['catchphrase']?.toString() ?? '陪你待一会儿～',
      systemPrompt: data['systemPrompt']?.toString() ?? '你是一只可爱的桌面宠物，说话简短。',
    );
  }

  Map<String, dynamic> toJson() => {
        'traits': traits,
        'tone': tone,
        'greeting': greeting,
        'catchphrase': catchphrase,
        'systemPrompt': systemPrompt,
      };
}

@immutable
class PetAnimSequence {
  const PetAnimSequence({required this.fps, required this.frames});

  final double fps;
  final List<String> frames;

  /// 按秒数取当前帧。用单调时间调用时不会在 20 秒等整数倍处跳帧。
  String frameAt(double seconds) {
    if (frames.isEmpty) return '';
    final rate = fps > 0 ? fps : 8.0;
    final index = (seconds * rate).floor() % frames.length;
    return frames[index];
  }

  /// 按序号取帧：绕垂直轴转身时，帧号代表朝向而不是时间。
  String frameAtIndex(int index) {
    if (frames.isEmpty) return '';
    return frames[index % frames.length];
  }
}

/// 宠物主体
@immutable
class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.personality,
    required this.palette,
    required this.accent,
    required this.anchors,
    required this.frames,
    this.animations = const {},
    required this.builtin,
    required this.heightRatio,
    required this.cutout,
    this.directory,
    this.assetRoot = '',
  });

  final String id;
  final String name;
  final PetPersonality personality;
  final List<Color> palette;
  final Color accent;
  final PetAnchors anchors;

  /// 表情 -> 文件名（相对 [directory] 或 [assetRoot]）
  final Map<PetMood, String> frames;

  /// 动作名 -> 逐帧动画序列（walk / run / lie）。空 map 表示只有单帧，用程序化姿态。
  final Map<String, PetAnimSequence> animations;
  final bool builtin;
  final double heightRatio;

  /// 抠图方式：rembg / flat / grabcut / oval / drawn
  final String cutout;

  /// 自定义宠物在磁盘上的目录
  final String? directory;

  /// 内置宠物的 asset 根目录
  final String assetRoot;

  factory Pet.fromPack(
    Map<String, dynamic> pack, {
    required String id,
    String? directory,
    bool builtin = false,
    String assetRoot = '',
  }) {
    final rawFrames = (pack['frames'] as Map?) ?? const {'idle': 'idle.png'};
    final frames = <PetMood, String>{};
    rawFrames.forEach((key, value) {
      final mood = PetMoodParsing.fromKey(key.toString());
      if (value != null) frames[mood] = value.toString();
    });
    if (!frames.containsKey(PetMood.idle)) {
      frames[PetMood.idle] = frames.values.isEmpty ? 'idle.png' : frames.values.first;
    }

    final palette = <Color>[];
    for (final value in (pack['palette'] as List? ?? const [])) {
      final color = _parseColor(value.toString());
      if (color != null) palette.add(color);
    }
    if (palette.isEmpty) palette.add(const Color(0xFFF7AA5F));

    final animations = <String, PetAnimSequence>{};
    final rawAnims = (pack['animations'] as Map?) ?? const {};
    rawAnims.forEach((key, value) {
      if (value is Map) {
        final animFrames = (value['frames'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
        if (animFrames.isNotEmpty) {
          animations[key.toString()] = PetAnimSequence(
            fps: (value['fps'] as num?)?.toDouble() ?? 8,
            frames: animFrames,
          );
        }
      }
    });

    final metrics = (pack['metrics'] as Map?) ?? const {};
    return Pet(
      id: id,
      name: pack['name']?.toString() ?? '小家伙',
      personality: PetPersonality.fromJson(pack['personality'] as Map<String, dynamic>?),
      palette: palette,
      accent: _parseColor(pack['accent']?.toString() ?? '') ?? palette.first,
      anchors: PetAnchors.fromJson(pack['anchors'] as Map<String, dynamic>?),
      frames: frames,
      animations: animations,
      builtin: builtin,
      heightRatio: (metrics['heightRatio'] as num?)?.toDouble() ?? 0.8,
      cutout: (metrics['cutout'] as String?) ?? 'unknown',
      directory: directory,
      assetRoot: assetRoot,
    );
  }

  String frameFile(PetMood mood) => frames[mood] ?? frames[PetMood.idle]!;

  ImageProvider imageFor(PetMood mood) => imageForFile(frameFile(mood));

  /// 按文件名取图（动画帧用），路径规则与 [imageFor] 一致。
  ImageProvider imageForFile(String file) {
    // 旧函数体继续作为 imageForFile 的实现。
    if (builtin) return AssetImage('$assetRoot/$file');
    return FileImage(File('${directory ?? ''}/$file'));
  }

  bool get supportsBlink => frames.containsKey(PetMood.blink);

  Map<String, dynamic> toPack() => {
        'schemaVersion': 1,
        'name': name,
        'personality': personality.toJson(),
        'palette': palette.map((c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}').toList(),
        'accent': '#${accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
        'anchors': {
          'head': [anchors.head.dx, anchors.head.dy],
          'headRadius': anchors.headRadius,
          'body': [anchors.body.dx, anchors.body.dy],
        },
        'metrics': {'heightRatio': heightRatio, 'cutout': cutout, 'style': 'sticker'},
        'frames': frames.map((mood, file) => MapEntry(mood.name, file)),
        if (animations.isNotEmpty)
          'animations': animations.map(
            (key, anim) => MapEntry(key, {'fps': anim.fps, 'frames': anim.frames}),
          ),
        'source': builtin ? 'builtin' : 'photo',
      };
}

Color? _parseColor(String raw) {
  var value = raw.trim().replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}
