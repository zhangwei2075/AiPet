import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/model_presets.dart';
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

    test('接口协议往返，非法协议回退 openai', () {
      final settings = AppSettings.fromJson({'apiProtocol': 'anthropic'});
      expect(settings.apiProtocol, 'anthropic');

      final round = AppSettings.fromJson(settings.toJson());
      expect(round.apiProtocol, 'anthropic');

      expect(AppSettings.fromJson({'apiProtocol': 'grpc'}).apiProtocol, 'openai');
      expect(const AppSettings().apiProtocol, 'openai');
    });
  });

  group('模型预设（Harness 可插拔）', () {
    test('每个预设的协议合法，端点非空且不带重复斜杠', () {
      for (final preset in modelPresets) {
        expect(const {'openai', 'anthropic'}, contains(preset.protocol),
            reason: '${preset.id} 协议非法');
        expect(preset.baseUrl.trim().isNotEmpty, isTrue, reason: '${preset.id} 地址为空');
        expect(preset.model.trim().isNotEmpty, isTrue, reason: '${preset.id} 模型名为空');
        expect(preset.baseUrl.endsWith('/'), isFalse, reason: '${preset.id} 末尾多余斜杠');
      }
    });

    test('Anthropic 预设走 /messages 端点（base 不能以 /v1 结尾）', () {
      for (final preset in modelPresets.where((p) => p.protocol == 'anthropic')) {
        expect(preset.baseUrl.endsWith('/v1'), isFalse,
            reason: '${preset.id} 以 /v1 结尾，拼出的 /v1/messages 多数服务不认');
      }
    });

    test('一键套用只动模型三件套，Key 与其它设置保留', () {
      const before = AppSettings(
        apiKey: 'sk-keep-me',
        scale: 0.42,
        forgeUrl: 'http://custom:9999',
      );
      final deepseek = modelPresets.firstWhere((p) => p.id == 'deepseek-openai');
      final after = deepseek.apply(before);

      expect(after.chatBackend, ChatBackendKind.openai);
      expect(after.apiProtocol, 'openai');
      expect(after.baseUrl, 'https://api.deepseek.com');
      expect(after.model, 'deepseek-v4-flash');
      expect(after.apiKey, 'sk-keep-me');
      expect(after.scale, 0.42);
      expect(after.forgeUrl, 'http://custom:9999');
    });

    test('反查：三件套完全一致才命中预设，改一项即自定义', () {
      final preset = modelPresets.firstWhere((p) => p.id == 'glm-coding-anthropic');
      expect(findPresetId(preset.apply(const AppSettings())), 'glm-coding-anthropic');
      expect(
        findPresetId(preset.apply(const AppSettings()).copyWith(model: 'glm-other')),
        customPresetId,
      );
      expect(findPresetId(const AppSettings()), customPresetId);
    });

    test('工具能力标注与协议一致（探测目前只支持 OpenAI）', () {
      for (final preset in modelPresets) {
        expect(preset.supportsTools, preset.protocol == 'openai');
        expect(preset.tools.isNotEmpty, isTrue);
      }
    });

    test('未知 id 返回空，自定义哨兵不可套用', () {
      expect(presetById('不存在的预设'), isNull);
      expect(presetById(customPresetId), isNull);
    });

    test('供应商分组：OpenCode Go / 按量排在前面，一个 Key 覆盖多模型', () {
      expect(modelProviders.first.id, 'opencode-go');
      expect(modelProviders[1].id, 'opencode-payg');
      final go = modelProviders.first;
      expect(go.models.length, greaterThan(3));
      expect(go.keyPrefixHint, 'oc_sk_');
      // 同一供应商下所有模型共享网关地址，只有 model 不同 —— 这就是「只填 Key」的前提
      expect(go.models.map((p) => p.baseUrl).toSet().length, 2); // OpenAI 端点 + Anthropic 端点
      expect(go.models.every((p) => p.protocol == 'openai' || p.protocol == 'anthropic'), isTrue);
    });

    test('OpenCode Go 端点正确（/inference/go + 协议路径）', () {
      final go = providerById('opencode-go')!;
      final openaiModel = go.models.firstWhere((p) => p.protocol == 'openai');
      final anthropicModel = go.models.firstWhere((p) => p.protocol == 'anthropic');
      expect(openaiModel.baseUrl, 'https://opencode.ai/inference/go/openai/v1');
      expect(anthropicModel.baseUrl, 'https://opencode.ai/inference/go/anthropic/v1');
      expect(
        providerById('opencode-payg')!.models.first.baseUrl,
        'https://opencode.ai/inference/openai/v1',
      );
    });

    test('选供应商套用后能反查回同一供应商', () {
      for (final provider in modelProviders) {
        final applied = provider.models.first.apply(const AppSettings());
        expect(providerOf(applied)?.id, provider.id, reason: '${provider.id} 反查失败');
      }
    });
  });

  group('OpenCode Go 会话头', () {
    test('仅 OpenCode 网关识别并生成稳定会话 ID', () {
      final local = AppSettings(baseUrl: 'http://127.0.0.1:11434/v1', apiKey: 'sk-x');
      final go = AppSettings(
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        apiKey: 'oc_sk_test',
      );
      expect(local.isOpencodeGateway, isFalse);
      expect(go.isOpencodeGateway, isTrue);
      expect(go.opencodeSessionId, startsWith('ses_'));
    });

    test('同一配置会话 ID 稳定，换 Key / 换地址即变化', () {
      const a = AppSettings(
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        apiKey: 'oc_sk_same',
      );
      const b = AppSettings(
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        apiKey: 'oc_sk_same',
      );
      const otherKey = AppSettings(
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        apiKey: 'oc_sk_other',
      );
      const otherUrl = AppSettings(
        baseUrl: 'https://opencode.ai/inference/openai/v1',
        apiKey: 'oc_sk_same',
      );
      expect(a.opencodeSessionId, b.opencodeSessionId);
      expect(a.opencodeSessionId, isNot(otherKey.opencodeSessionId));
      expect(a.opencodeSessionId, isNot(otherUrl.opencodeSessionId));
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
