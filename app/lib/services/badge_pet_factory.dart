import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/settings.dart';
import 'persona.dart';

/// 无法连接 PetForge 时的兜底：把照片做成「猫耳徽章」宠物，
/// 保证「用照片生成」在离线状态下也能走通。
class BadgePetFactory {
  static const int _size = 640;

  Future<GeneratedPet> build(Uint8List bytes, {String? name}) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final side = math.min(image.width, image.height).toDouble();
    final src = Rect.fromCenter(
      center: Offset(image.width / 2, image.height / 2),
      width: side,
      height: side,
    );

    final accent = await _accentOf(image);
    final persona = buildLocalPersona(accent);
    final displayName = (name == null || name.trim().isEmpty) ? persona.name : name.trim();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(_size / 2, _size / 2 + 18);
    const radius = 232.0;

    // 猫耳（在头像后面）
    final earPaint = Paint()..color = accent;
    final earInner = Paint()..color = Color.lerp(accent, Colors.white, 0.55)!;
    for (final flip in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(center.dx + flip * 138, center.dy - 128);
      canvas.rotate(flip * 0.12);
      final ear = Path()
        ..moveTo(-62, 92)
        ..quadraticBezierTo(-70, -46, 0, -86)
        ..quadraticBezierTo(70, -46, 62, 92)
        ..close();
      canvas.drawPath(ear, earPaint);
      canvas.scale(0.52, 0.62);
      final inner = Path()
        ..moveTo(-62, 92)
        ..quadraticBezierTo(-70, -46, 0, -86)
        ..quadraticBezierTo(70, -46, 62, 92)
        ..close();
      canvas.drawPath(inner, earInner);
      canvas.restore();
    }

    // 圆形照片
    final circle = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(image, src, circle.inflate(1), paint);
    canvas.restore();

    // 白色描边 + 彩色内圈
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      radius - 15,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = accent.withValues(alpha: 0.85),
    );

    // 左上高光
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawOval(
      Rect.fromCenter(center: center + const Offset(-74, -96), width: 132, height: 66),
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final output = await picture.toImage(_size, _size);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('无法编码图片');
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final hex = _hex(accent);
    final pack = <String, dynamic>{
      'schemaVersion': 1,
      'name': displayName,
      'personality': {
        'traits': persona.traits,
        'tone': '短句、口语化、偶尔用颜文字，每次不超过 40 字',
        'greeting': persona.greeting.replaceFirst(persona.name, displayName),
        'catchphrase': '在你桌面上待着～',
        'systemPrompt': persona.systemPrompt.replaceFirst('「${persona.name}」', '「$displayName」'),
      },
      'palette': [hex, '#ffffff', _hex(Color.lerp(accent, Colors.black, 0.25)!)],
      'accent': hex,
      'anchors': {
        'head': [0.5, 0.42],
        'headRadius': 0.27,
        'body': [0.5, 0.78],
      },
      'metrics': {'cutout': 'badge', 'heightRatio': 0.9, 'style': 'badge'},
      'frames': {'idle': 'base.png'},
      'source': 'photo',
    };
    image.dispose();
    codec.dispose();
    return GeneratedPet(pack: pack, images: {'base': png}, elapsedMs: 0);
  }

  Future<Color> _accentOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return const Color(0xFFF7AA5F);
    var r = 0.0, g = 0.0, b = 0.0, weight = 0.0;
    final bytes = data.buffer.asUint8List();
    final step = math.max(4, (image.width * image.height ~/ 4000)) * 4;
    for (var i = 0; i < bytes.length - 3; i += step) {
      final pr = bytes[i], pg = bytes[i + 1], pb = bytes[i + 2];
      final hsv = HSVColor.fromColor(Color.fromARGB(255, pr, pg, pb));
      if (hsv.saturation < 0.15) continue;
      if (hsv.value < 0.15 || hsv.value > 0.97) continue;
      final w = hsv.saturation;
      r += pr * w;
      g += pg * w;
      b += pb * w;
      weight += w;
    }
    if (weight < 1) return const Color(0xFFF7AA5F);
    return Color.fromARGB(255, (r / weight).round(), (g / weight).round(), (b / weight).round());
  }

  String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }
}
