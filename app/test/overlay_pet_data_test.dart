import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/mobile/overlay_pet_data.dart';
import 'package:momopet/models/pet.dart';

void main() {
  test('自定义宠物经共享数据往返后保留目录、帧与动画', () {
    final pet = Pet.fromPack(
      {
        'name': '有财',
        'palette': ['#ec6627'],
        'frames': {'idle': 'base.png'},
        'animations': {
          'walk': {
            'fps': 8,
            'frames': ['walk_0.png', 'walk_1.png'],
          },
        },
      },
      id: 'p1',
      directory: r'C:\pets\p1',
    );

    final decoded = petFromOverlayPayload(
      jsonDecode(jsonEncode(overlayPayload(pet, updatedAt: 123))) as Map<String, dynamic>,
    );

    expect(decoded, isNotNull);
    expect(decoded!.name, '有财');
    expect(decoded.builtin, isFalse);
    expect(decoded.directory, r'C:\pets\p1');
    expect(decoded.animations['walk']!.frames, ['walk_0.png', 'walk_1.png']);
    expect(decoded.frameFile(PetMood.idle), 'base.png');
  });

  test('内置宠物经共享数据往返后保留 assetRoot', () {
    final pet = Pet.fromPack(
      {
        'name': '小黄豆',
        'frames': {'idle': 'idle.png', 'happy': 'happy.png'},
      },
      id: 'doudou',
      builtin: true,
      assetRoot: 'assets/pets/doudou',
    );

    final decoded = petFromOverlayPayload(overlayPayload(pet));

    expect(decoded, isNotNull);
    expect(decoded!.builtin, isTrue);
    expect(decoded.assetRoot, 'assets/pets/doudou');
    expect((decoded.imageFor(PetMood.happy) as AssetImage).assetName,
        'assets/pets/doudou/happy.png');
  });

  test('坏数据返回 null，让悬浮窗回退到内置 momo', () {
    expect(petFromOverlayPayload(const {}), isNull);
    expect(petFromOverlayPayload({'pack': 'not-a-map'}), isNull);
  });
}
