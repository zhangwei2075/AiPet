import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/services/petforge_client.dart';

/// 端到端：用真实的 PetForgeClient 走「上传自定义照片 → 生成卡通宠物」链路。
///
/// 需要先启动服务（scripts\start-petforge.ps1）；没启动时本测试直接跳过，
/// 不影响其余用例。服务地址可用 PETFORGE_URL 覆盖。
void main() {
  final baseUrl = Platform.environment['PETFORGE_URL'] ?? 'http://127.0.0.1:8787';
  // 测试图可用 PETFORGE_TEST_IMAGE 覆盖，默认用服务自带的样例照片
  final photo = File(Platform.environment['PETFORGE_TEST_IMAGE'] ?? '../services/petforge/tests/sample_photo.jpg');

  test('上传照片生成卡通宠物（PetForgeClient 端到端）', () async {
    final client = PetForgeClient();
    final health = await client.health(baseUrl);
    if (!health.online) {
      // ignore: avoid_print
      print('跳过：PetForge 未启动（$baseUrl），先运行 scripts\\start-petforge.ps1');
      return;
    }

    expect(photo.existsSync(), isTrue, reason: '找不到测试照片 ${photo.path}');

    final generated = await client.generate(
      bytes: await photo.readAsBytes(),
      baseUrl: baseUrl,
      filename: 'sample_photo.jpg',
      style: 'sticker',
      animate: true,
    );

    final pack = generated.pack;
    final metrics = (pack['metrics'] as Map?) ?? const {};

    // 结果应该是一份能被应用解析的 petpack
    expect(pack['schemaVersion'], 1);
    expect(pack['name'], isNotEmpty);
    expect(metrics['cutout'], anyOf('rembg', 'flat', 'grabcut', 'oval'));
    expect(metrics['style'], 'sticker');
    expect(generated.images['base'], isNotNull);
    expect(generated.images['base']!.length, greaterThan(1024));
    expect(generated.elapsedMs, greaterThan(0));

    final anchors = (pack['anchors'] as Map?) ?? const {};
    expect(anchors['head'], isNotNull);
    expect(anchors['headRadius'], greaterThan(0));

    // 与应用一致的解析入口
    final pet = Pet.fromPack(pack, id: 'e2e');
    expect(pet.name, pack['name']);
    expect(pet.heightRatio, greaterThan(0.1));
    expect(pet.accent.toARGB32(), isNonZero);

    // 动画帧：walk / run / lie 至少各有一条，且文件都能在响应里找到
    expect(pet.animations, isNotEmpty);
    for (final entry in pet.animations.entries) {
      expect(entry.value.frames.length, greaterThanOrEqualTo(2), reason: entry.key);
      for (final frame in entry.value.frames) {
        expect(generated.images[frame.replaceAll('.png', '')], isNotNull, reason: frame);
      }
    }

    // ignore: avoid_print
    print('生成成功：${pet.name}  cutout=${metrics['cutout']}  '
        '动画=${pet.animations.keys.join('/')}  '
        'elapsed=${generated.elapsedMs}ms  图片=${(generated.images['base']!.length / 1024).toStringAsFixed(0)}KB');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
