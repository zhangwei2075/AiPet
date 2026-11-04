import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/settings.dart';
import 'package:momopet/services/persona.dart';

void main() {
  group('AppSettings', () {
    test('默认值可用', () {
      const settings = AppSettings();
      expect(settings.scale, 0.25);
      expect(settings.chatBackend, ChatBackendKind.local);
      expect(settings.alwaysOnTop, isTrue);
    });

    test('JSON 往返保持字段', () {
      const settings = AppSettings(
        activePetId: 'p1',
        scale: 1.25,
        chatBackend: ChatBackendKind.openai,
        baseUrl: 'http://127.0.0.1:1234/v1',
        model: 'qwen2.5:7b',
        forgeUrl: 'http://127.0.0.1:8787',
        updateManifestUrl: 'https://example.com/update.json',
        autoCheckUpdates: false,
        petWindowPosition: '100,200',
      );

      final restored = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );

      expect(restored.activePetId, 'p1');
      expect(restored.scale, 1.25);
      expect(restored.chatBackend, ChatBackendKind.openai);
      expect(restored.baseUrl, 'http://127.0.0.1:1234/v1');
      expect(restored.model, 'qwen2.5:7b');
      expect(restored.updateManifestUrl, 'https://example.com/update.json');
      expect(restored.autoCheckUpdates, isFalse);
      expect(restored.petWindowPosition, '100,200');
    });

    test('缩放值被夹在 0.1~3.0（scaleV=2 新刻度）', () {
      expect(AppSettings.fromJson({'scale': 5.0, 'scaleV': 2}).scale, 3.0);
      expect(AppSettings.fromJson({'scale': 0.05, 'scaleV': 2}).scale, 0.1);
      expect(AppSettings.fromJson({'scale': 0.25, 'scaleV': 2}).scale, 0.25);
    });

    test('坏数据回落到默认值', () {
      final settings = AppSettings.fromJson(
          {'chatBackend': 'unknown', 'scale': '大', 'scaleV': 2});
      expect(settings.chatBackend, ChatBackendKind.local);
      expect(settings.scale, 0.25);
    });

    test('无 scaleV 的旧刻度一律废弃回默认 0.25', () {
      expect(AppSettings.fromJson({'scale': 1.2}).scale, 0.25);
      expect(AppSettings.fromJson({'scale': 5.0}).scale, 0.25);
    });
  });

  group('buildLocalPersona', () {
    test('同一主色得到同一只宠物', () {
      final a = buildLocalPersona(const Color(0xFFF7AA5F));
      final b = buildLocalPersona(const Color(0xFFF7AA5F));
      expect(a.name, b.name);
      expect(a.traits, b.traits);
    });

    test('名字与提示词都非空且含名字', () {
      final persona = buildLocalPersona(const Color(0xFF8FD8C6));
      expect(persona.name.trim(), isNotEmpty);
      expect(persona.personalityInPrompt, isTrue);
    });

    test('不同主色给出不同名字池', () {
      final warm = buildLocalPersona(const Color(0xFFF7AA5F));
      final cool = buildLocalPersona(const Color(0xFF3F6BD8));
      expect(warm.name, isNot(cool.name));
    });
  });
}

extension on LocalPersona {
  bool get personalityInPrompt => systemPrompt.contains(name) && systemPrompt.contains('桌面宠物');
}
