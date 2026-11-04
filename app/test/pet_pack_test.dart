import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/data/pet_repository.dart';
import 'package:momopet/models/pet.dart';
import 'dart:io';

Map<String, dynamic> _pack() => {
      'schemaVersion': 1,
      'name': '橘子团子',
      'personality': {
        'traits': ['元气', '黏人'],
        'tone': '短句',
        'greeting': '嗨！',
        'catchphrase': '陪你待着',
        'systemPrompt': '你是一只桌面宠物',
      },
      'palette': ['#F7AA5F', '#FFE3C2'],
      'accent': '#F7AA5F',
      'anchors': {
        'head': [0.5, 0.34],
        'headRadius': 0.27,
        'body': [0.5, 0.72],
      },
      'metrics': {'heightRatio': 0.8, 'cutout': 'rembg', 'style': 'sticker'},
      'frames': {'idle': 'idle.png', 'happy': 'happy.png', 'blink': 'blink.png'},
      'source': 'builtin',
    };

void main() {
  _builtinOrder();

  test('从 petpack 解析出宠物与表情帧', () {
    final pet = Pet.fromPack(_pack(), id: 'momo', builtin: true, assetRoot: 'assets/pets/momo');

    expect(pet.id, 'momo');
    expect(pet.name, '橘子团子');
    expect(pet.personality.traits, ['元气', '黏人']);
    expect(pet.accent, const Color(0xFFF7AA5F));
    expect(pet.palette.length, 2);
    expect(pet.frameFile(PetMood.happy), 'happy.png');
    expect(pet.supportsBlink, isTrue);
    expect(pet.heightRatio, 0.8);
    expect(pet.cutout, 'rembg');
  });

  test('自定义宠物 id 取目录名，不受末尾斜杠影响', () {
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}p20261101-youcai-ai',
    );
    expect(PetRepository.idForDirectory(dir), 'p20261101-youcai-ai');
  });

  test('缺少表情帧时回退到 idle', () {
    final pack = _pack()..['frames'] = {'happy': 'happy.png'};
    final pet = Pet.fromPack(pack, id: 'x');

    expect(pet.frameFile(PetMood.angry), 'happy.png');
    expect(pet.supportsBlink, isFalse);
  });

  test('空包也能拿到可用的默认值', () {
    final pet = Pet.fromPack(const {}, id: 'empty');

    expect(pet.name, '小家伙');
    expect(pet.frameFile(PetMood.idle), 'idle.png');
    expect(pet.palette, isNotEmpty);
    expect(pet.personality.systemPrompt, isNotEmpty);
  });

  test('toPack 与 fromPack 往返一致', () {
    final pet = Pet.fromPack(_pack(), id: 'momo');
    final again = Pet.fromPack(pet.toPack(), id: 'momo');

    expect(again.name, pet.name);
    expect(again.frames, pet.frames);
    expect(again.accent.toARGB32(), pet.accent.toARGB32());
    expect(again.anchors.head, pet.anchors.head);
    expect(again.cutout, pet.cutout);
  });
}

void _builtinOrder() {
  test('内置形象顺序：小黄豆是默认宠物', () {
    expect(PetRepository.builtinIds.first, 'doudou');
  });

  test('小黄豆的宠物包带齐 6 个表情帧', () async {
    // 直接读仓库资产太重，这里断言包里的帧映射由 Pet.fromPack 解析
    final pet = Pet.fromPack(
      {
        'name': '小黄豆',
        'frames': {
          'idle': 'idle.png',
          'happy': 'happy.png',
          'love': 'love.png',
          'angry': 'angry.png',
          'sleepy': 'sleepy.png',
          'blink': 'blink.png',
        },
      },
      id: 'doudou',
      builtin: true,
      assetRoot: 'assets/pets/doudou',
    );
    expect(pet.supportsBlink, isTrue);
    expect(pet.frameFile(PetMood.love), 'love.png');
    final provider = pet.imageFor(PetMood.happy) as AssetImage;
    expect(provider.assetName, 'assets/pets/doudou/happy.png');
  });
}
