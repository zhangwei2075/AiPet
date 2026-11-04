import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/pet.dart';

Map<String, dynamic> samplePack() => jsonDecode(jsonEncode({
      'name': '小黄豆',
      'frames': {'idle': 'idle.png', 'happy': 'happy.png'},
      'animations': {
        'walk': {'fps': 8, 'frames': ['walk_0.png', 'walk_1.png']},
        'run': {
          'fps': 12,
          'frames': ['run_0.png', 'run_1.png', 'run_2.png', 'run_3.png'],
        },
        'lie': {'fps': 2.5, 'frames': ['lie_0.png', 'lie_1.png']},
      },
    })) as Map<String, dynamic>;

void main() {
  test('fromPack 解析逐帧动画', () {
    final pet = Pet.fromPack(samplePack(), id: 'doudou',
        builtin: true, assetRoot: 'assets/pets/doudou');

    expect(pet.animations, hasLength(3));
    expect(pet.animations['walk']!.fps, 8);
    expect(pet.animations['walk']!.frames, ['walk_0.png', 'walk_1.png']);
    expect(pet.animations['run']!.frames, hasLength(4));
    expect(pet.animations['lie']!.fps, 2.5);
  });

  test('无 animations 的旧包兼容：动画为空', () {
    final pet = Pet.fromPack({
      'name': '老包',
      'frames': {'idle': 'idle.png'},
    }, id: 'legacy');

    expect(pet.animations, isEmpty);
  });

  test('动画缺 frames 或为空时忽略，fps 缺省 8', () {
    final pet = Pet.fromPack({
      'animations': {
        'walk': {'frames': []},
        'run': {'frames': ['run_0.png']},
      },
    }, id: 'x');

    expect(pet.animations.keys, ['run']);
    expect(pet.animations['run']!.fps, 8);
  });

  test('toPack 序列化 animations 并可回读', () {
    final pet = Pet.fromPack(samplePack(), id: 'x');
    final round = Pet.fromPack(pet.toPack(), id: 'x');

    expect(round.animations.keys, pet.animations.keys);
    expect(round.animations['run']!.frames, pet.animations['run']!.frames);
    expect(round.animations['lie']!.fps, pet.animations['lie']!.fps);
  });

  test('frameAt 按 fps 循环，跨 20 秒不跳帧', () {
    const seq = PetAnimSequence(fps: 8, frames: ['a', 'b', 'c', 'd', 'e', 'f']);
    expect(seq.frameAt(0), 'a');
    expect(seq.frameAt(0.125), 'b');
    expect(seq.frameAt(0.75), 'a');

    // 旧实现用 _clock.value * 20，20 秒回绕时帧号会突然跳变；
    // 单调时间下相邻采样必须保持连续。
    final before = seq.frameAt(19.875);
    final after = seq.frameAt(20.0);
    final beforeIndex = seq.frames.indexOf(before);
    final afterIndex = seq.frames.indexOf(after);
    expect((beforeIndex + 1) % seq.frames.length, afterIndex);

    const slow = PetAnimSequence(fps: 0, frames: ['x', 'y']);
    expect(slow.frameAt(0.13), 'y'); // fps 非法时回退 8
    const empty = PetAnimSequence(fps: 8, frames: []);
    expect(empty.frameAt(1), '');
  });

  test('imageForFile 路径规则与 imageFor 一致', () {    final builtin = Pet.fromPack(samplePack(), id: 'doudou',
        builtin: true, assetRoot: 'assets/pets/doudou');
    expect((builtin.imageForFile('walk_0.png') as AssetImage).assetName,
        'assets/pets/doudou/walk_0.png');
    expect((builtin.imageFor(PetMood.idle) as AssetImage).assetName,
        'assets/pets/doudou/idle.png');

    final custom = Pet.fromPack(samplePack(), id: 'c1',
        directory: r'C:\pets\c1');
    expect((custom.imageForFile('run_2.png') as FileImage).file.path,
        r'C:\pets\c1/run_2.png'); // File 拼接在 Windows 保留混合分隔符
    expect((custom.imageFor(PetMood.happy) as FileImage).file.path,
        r'C:\pets\c1/happy.png');
  });
}
