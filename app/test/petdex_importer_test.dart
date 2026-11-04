import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/services/petdex_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('识别 8×9 / 8×11 图集与单元格尺寸', () {
    final v1 = detectPetdexLayout(1536, 1872, version: 1);
    expect(v1, isNotNull);
    expect(v1!.rows, 9);
    expect(v1.cellWidth, 192);
    expect(v1.cellHeight, 208);

    final v2 = detectPetdexLayout(1536, 2288, version: 2);
    expect(v2, isNotNull);
    expect(v2!.rows, 11);
    expect(v2.cellWidth, 192);
    expect(v2.cellHeight, 208);

    // 没写 version 时按比例推断
    expect(detectPetdexLayout(1536, 1872)!.rows, 9);
    expect(detectPetdexLayout(1536, 2288)!.rows, 11);

    // 不是 8 列或比例不对
    expect(detectPetdexLayout(1000, 1000), isNull);
    expect(detectPetdexLayout(1536, 1800, version: 1), isNull);
  });

  test('扫描 ~/.codex/pets 结构（临时目录）', () async {
    final root = await Directory.systemTemp.createTemp('petdex-scan-');
    addTearDown(() => root.delete(recursive: true));
    final folder = Directory('${root.path}${Platform.pathSeparator}boba')..createSync();
    File('${folder.path}${Platform.pathSeparator}pet.json').writeAsStringSync(
      jsonEncode({
        'id': 'boba',
        'displayName': 'Boba',
        'description': 'otter',
        'spriteVersionNumber': 2,
        'spritesheetPath': 'sheet.webp',
      }),
    );
    File('${folder.path}${Platform.pathSeparator}sheet.webp').writeAsBytesSync([1, 2, 3]);

    final pets = await PetdexImporter(root: root).scan();

    expect(pets, hasLength(1));
    expect(pets.first.name, 'Boba');
    expect(pets.first.description, 'otter');
    expect(pets.first.version, 2);
  });

  test('导入本机已安装的 boba（没有就跳过）', () async {
    final importer = PetdexImporter();
    final pets = await importer.scan();
    PetdexPet? boba;
    for (final pet in pets) {
      if (pet.id == 'boba') boba = pet;
    }
    if (boba == null) return;

    final generated = await importer.import(boba);
    final animations = generated.pack['animations'] as Map<String, dynamic>;
    expect(animations['idle']['frames'], hasLength(6));
    expect(animations['walk']['frames'], hasLength(8));
    expect(animations['hop']['frames'], hasLength(5));
    expect(generated.images, isNotEmpty);

    final bytes = generated.images.values.first;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, frame.image.height);
    frame.image.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
