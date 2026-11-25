import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';

/// 人设覆盖：设置里的人设优先于宠物包，且能完整 JSON 往返。
/// 这条链路一旦断了，用户改完人设会发现聊天语气完全没变。
void main() {
  const packPersona = PetPersonality(
    traits: ['元气', '黏人'],
    tone: '短句、可爱',
    greeting: '嗨，我是有财！',
    catchphrase: '陪你待一会儿～',
    systemPrompt: '你是一只有财，说话简短。',
  );

  const pet = Pet(
    id: 'youcai',
    name: '有财',
    personality: packPersona,
    palette: [Color(0xFFF0A35E)],
    accent: Color(0xFFF0A35E),
    anchors: PetAnchors(),
    frames: {PetMood.idle: 'idle.png'},
    builtin: true,
    heightRatio: 0.8,
    cutout: 'drawn',
    assetRoot: 'assets/pets/youcai',
  );

  test('没有自定义时用宠物包自带人设', () {
    const settings = AppSettings();
    expect(settings.personaOf(pet).greeting, packPersona.greeting);
    expect(settings.hasCustomPersona(pet.id), isFalse);
  });

  test('设置里的人设覆盖宠物包', () {
    const custom = PetPersonality(
      traits: ['话痨'],
      tone: '欢脱',
      greeting: '我回来啦！',
      catchphrase: '今天也要加油哦',
      systemPrompt: '你是话痨版有财。',
    );
    final settings = const AppSettings()
        .copyWith(petPersonas: {pet.id: custom});
    expect(settings.personaOf(pet).greeting, '我回来啦！');
    expect(settings.personaOf(pet).traits, ['话痨']);
    expect(settings.hasCustomPersona(pet.id), isTrue);
  });

  test('人设 JSON 往返不丢字段', () {
    const custom = PetPersonality(
      traits: ['爱操心', '话痨'],
      tone: '慢条斯理',
      greeting: '回来啦',
      catchphrase: '记得喝水',
      systemPrompt: '你是爱操心的有财。',
    );
    final settings =
        const AppSettings().copyWith(petPersonas: {pet.id: custom});
    final restored = AppSettings.fromJson(settings.toJson());
    final persona = restored.personaOf(pet);
    expect(persona.traits, custom.traits);
    expect(persona.tone, custom.tone);
    expect(persona.greeting, custom.greeting);
    expect(persona.catchphrase, custom.catchphrase);
    expect(persona.systemPrompt, custom.systemPrompt);
  });

  test('坏掉的人设节点被跳过，不影响整体设置', () {
    final restored = AppSettings.fromJson({
      'scaleV': 2,
      'petPersonas': {
        pet.id: 'not-a-map',
        'other': {
          'traits': ['安静'],
          'tone': '轻声',
          'greeting': '嗯',
          'catchphrase': '…',
          'systemPrompt': '安静一点。',
        },
      },
    });
    expect(restored.hasCustomPersona(pet.id), isFalse);
    expect(restored.petPersonas['other']!.traits, ['安静']);
  });

  test('withIdentity 只换名字与人设，图片与目录保持不变', () {
    const custom = PetPersonality(
      traits: ['安静'],
      tone: '轻声',
      greeting: '嗯',
      catchphrase: '…',
      systemPrompt: '安静一点。',
    );
    final speaker = pet.withIdentity(name: '发财', personality: custom);
    expect(speaker.name, '发财');
    expect(speaker.personality.tone, '轻声');
    expect(speaker.id, pet.id);
    expect(speaker.frames, pet.frames);
    expect(speaker.assetRoot, pet.assetRoot);
    expect(speaker.builtin, isTrue);
  });

  test('sameAs 用于判断有没有真的改过', () {
    expect(packPersona.sameAs(packPersona.copyWith()), isTrue);
    expect(packPersona.sameAs(packPersona.copyWith(tone: '别的')), isFalse);
    expect(packPersona.sameAs(packPersona.copyWith(traits: ['冷淡'])), isFalse);
  });
}
