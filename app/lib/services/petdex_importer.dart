import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/settings.dart';

/// 一个本机已安装的 Petdex / Codex 宠物。
@immutable
class PetdexPet {
  const PetdexPet({
    required this.folder,
    required this.id,
    required this.name,
    required this.description,
    required this.spritesheet,
    required this.version,
  });

  final String folder;
  final String id;
  final String name;
  final String description;
  final File spritesheet;
  final int version;

  static PetdexPet? fromFolder(Directory folder) {
    try {
      final jsonFile = File('${folder.path}${Platform.pathSeparator}pet.json');
      if (!jsonFile.existsSync()) return null;
      final map = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final sheetName = (map['spritesheetPath'] ?? 'spritesheet.webp').toString();
      final sheet = File('${folder.path}${Platform.pathSeparator}$sheetName');
      if (!sheet.existsSync()) return null;
      final fallbackId = folder.uri.pathSegments.where((s) => s.isNotEmpty).last;
      return PetdexPet(
        folder: folder.path,
        id: (map['id'] ?? fallbackId).toString(),
        name: (map['displayName'] ?? map['name'] ?? fallbackId).toString(),
        description: (map['description'] ?? '').toString(),
        spritesheet: sheet,
        version: (map['spriteVersionNumber'] as num?)?.toInt() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Petdex 图集几何：8 列，v1 9 行 / v2 11 行，单帧 192×208。
@immutable
class PetdexLayout {
  const PetdexLayout({
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
  });

  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;

  double get square => cellWidth > cellHeight ? cellWidth : cellHeight;
}

PetdexLayout? detectPetdexLayout(int width, int height, {int? version}) {
  if (width <= 0 || height <= 0) return null;
  final rows = version == 2
      ? 11
      : version == 1
          ? 9
          : (height * 1536 >= width * 2288 ? 11 : 9);
  if (width % 8 != 0 || height % rows != 0) return null;

  final cellWidth = width / 8;
  final cellHeight = height / rows;
  if (cellWidth < 16 || cellHeight < 16) return null;
  // 允许等比缩放，但拒绝明显不是 192×208 比例的图。
  if ((cellWidth / cellHeight - 192 / 208).abs() > 0.03) return null;
  return PetdexLayout(
    columns: 8,
    rows: rows,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );
}

class PetdexImportException implements Exception {
  const PetdexImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 读取 `~/.codex/pets/<slug>/pet.json + spritesheet`，转成我们的 petpack。
///
/// 只处理本机用户已经安装的宠物，不下载、不打包 Petdex 画廊素材。
class PetdexImporter {
  PetdexImporter({Directory? root}) : root = root ?? defaultRoot();

  final Directory root;

  static Directory defaultRoot() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    return Directory('$home${Platform.pathSeparator}.codex${Platform.pathSeparator}pets');
  }

  Future<List<PetdexPet>> scan() async {
    if (!await root.exists()) return const [];
    final pets = <PetdexPet>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final pet = PetdexPet.fromFolder(entity);
      if (pet != null) pets.add(pet);
    }
    pets.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return pets;
  }

  Future<GeneratedPet> import(PetdexPet source) async {
    final bytes = await source.spritesheet.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final sheet = frame.image;
    try {
      final layout = detectPetdexLayout(sheet.width, sheet.height, version: source.version);
      if (layout == null) {
        throw PetdexImportException(
          '图集尺寸不支持：${sheet.width}×${sheet.height}（需要 8×9 或 8×11 网格）',
        );
      }

      final images = <String, Uint8List>{};
      final idle = await _sliceRow(sheet, layout, 0, 6, 'idle', images);
      final walk = await _sliceRow(sheet, layout, 1, 8, 'walk', images);
      final wave = await _sliceRow(sheet, layout, 3, 4, 'wave', images);
      final jump = await _sliceRow(sheet, layout, 4, 5, 'jump', images);
      final failed = await _sliceRow(sheet, layout, 5, 8, 'failed', images);
      final waiting = await _sliceRow(sheet, layout, 6, 6, 'waiting', images);

      final pack = <String, dynamic>{
        'schemaVersion': 1,
        'name': source.name,
        'personality': {
          'traits': ['可爱', '安静'],
          'tone': '短句、口语化，每次不超过 40 字',
          'greeting': '嗨，我是${source.name}！',
          'catchphrase': '陪你待着',
          'systemPrompt':
              '你是一只名叫「${source.name}」的桌面宠物。说话简短、可爱，称呼主人为「主人」，'
              '永远保持角色，不要提及自己是 AI 或模型。回答时先输出 [情绪] 标签，'
              '情绪只能是 happy / love / angry / sleepy / idle 之一。',
        },
        'palette': <String>[],
        'anchors': {
          'head': [0.5, 0.24],
          'headRadius': 0.26,
          'body': [0.5, 0.72],
        },
        'metrics': {
          'heightRatio': 0.95,
          'cutout': 'petdex',
          'style': 'petdex',
        },
        'frames': {
          'idle': '${idle.first}.png',
          'happy': '${jump.first}.png',
          'love': '${wave.first}.png',
          'angry': '${failed.first}.png',
          'sleepy': '${waiting.first}.png',
          'blink': '${idle.length > 1 ? idle[1] : idle.first}.png',
        },
        'animations': {
          'idle': {'fps': 8, 'frames': idle.map((n) => '$n.png').toList()},
          'walk': {'fps': 8, 'frames': walk.map((n) => '$n.png').toList()},
          'run': {'fps': 10, 'frames': walk.map((n) => '$n.png').toList()},
          'lie': {'fps': 6, 'frames': waiting.map((n) => '$n.png').toList()},
          'hop': {'fps': 8, 'frames': jump.map((n) => '$n.png').toList()},
        },
        'source': 'petdex',
      };

      return GeneratedPet(pack: pack, images: images);
    } finally {
      sheet.dispose();
    }
  }

  Future<List<String>> _sliceRow(
    ui.Image sheet,
    PetdexLayout layout,
    int row,
    int count,
    String prefix,
    Map<String, Uint8List> images,
  ) async {
    final names = <String>[];
    final square = layout.square.round();
    final total = count.clamp(1, layout.columns);
    for (var col = 0; col < total; col++) {
      final source = Rect.fromLTWH(
        col * layout.cellWidth,
        row * layout.cellHeight,
        layout.cellWidth,
        layout.cellHeight,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.save();
      // Petdex 原画朝右；我们的 facing 约定是原画朝左，所以导入时水平翻转。
      canvas.translate(square.toDouble(), 0);
      canvas.scale(-1, 1);
      final destination = Rect.fromLTWH(
        (square - layout.cellWidth) / 2,
        square - layout.cellHeight,
        layout.cellWidth,
        layout.cellHeight,
      );
      canvas.drawImageRect(
        sheet,
        source,
        destination,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(square, square);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) continue;
      final name = '${prefix}_$col';
      images[name] = data.buffer.asUint8List();
      names.add(name);
    }
    if (names.isEmpty) {
      throw const PetdexImportException('图集里没有可用帧');
    }
    return names;
  }
}
