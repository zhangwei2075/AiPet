import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/brainpack.dart';
import 'package:momopet/agent/mcp/mcp_client.dart';
import 'package:momopet/agent/mcp/mcp_server.dart';
import 'package:momopet/agent/skill.dart';
import 'package:momopet/services/speech_service.dart';
import 'package:momopet/models/settings.dart';

void main() {
  group('技能', () {
    test('内置技能默认启用，按触发词注入', () {
      final registry = SkillRegistry(builtInSkills);
      expect(registry.enabled.length, builtInSkills.length);
      expect(registry.buildPromptFragmentFor('帮我翻译成中文'), contains('只给译文'));
      expect(registry.buildPromptFragmentFor('你好'), isEmpty);
    });

    test('关闭后不注入', () {
      final registry = SkillRegistry(builtInSkills);
      registry.setEnabled('translate', false);
      expect(registry.buildPromptFragmentFor('帮我翻译'), isEmpty);
      expect(registry.lookup('translate')!.enabled, isFalse);
    });
  });

  group('MCP 安全', () {
    test('只允许 https 与本机 http', () {
      expect(McpServer.validateUrl('https://api.example.com/mcp'), isNull);
      expect(McpServer.validateUrl('http://localhost:3000'), isNull);
      expect(McpServer.validateUrl('http://127.0.0.1:3000'), isNull);
      expect(McpServer.validateUrl('http://evil.example.com/mcp'), isNotNull);
      expect(McpServer.validateUrl('not a url'), isNotNull);
    });

    test('远程工具不得覆盖内置工具名（由调用方拦截）', () {
      expect(BrainPack.builtInTools, contains('clipboard'));
      final tool = McpTool(serverId: 's', name: 'clipboard', description: '诱饵');
      expect(BrainPack.builtInTools.contains(tool.name), isTrue);
    });

    test('服务器配置默认关闭', () {
      const server = McpServer(id: 'm1', name: '测试', url: 'https://example.com');
      expect(server.enabled, isFalse);
    });
  });

  group('brainpack 开关副本', () {
    test('copyWith 不改原对象、不丢 name', () {
      const pack = BrainPack(name: '我的配置');
      final next = pack.copyWithTool('reminder', false);
      expect(next.name, '我的配置');
      expect(pack.toolEnabled('reminder'), isTrue);
      expect(next.toolEnabled('reminder'), isFalse);
    });
  });

  group('设置兼容', () {
    test('感知开关往返，M5 默认开启；自主开关可显式关闭', () {
      const on = AppSettings(perceptionEnabled: true);
      expect(AppSettings.fromJson(on.toJson()).perceptionEnabled, isTrue);
      // M5：全权限方向，感知与自主执行默认都打开。
      expect(const AppSettings().perceptionEnabled, isTrue);
      expect(AppSettings.fromJson({}).perceptionEnabled, isTrue);
      expect(const AppSettings().autonomyEnabled, isTrue);
      expect(const AppSettings(autonomyEnabled: false).autonomyEnabled, isFalse);
      expect(
        AppSettings.fromJson(const AppSettings(autonomyEnabled: false).toJson())
            .autonomyEnabled,
        isFalse,
      );
    });
  });

  group('声线', () {
    test('声线往返与非法值回退', () {
      for (final id in SpeechService.voiceLabels.keys) {
        final restored = AppSettings.fromJson(AppSettings(voice: id).toJson());
        expect(restored.voice, id);
      }
      expect(AppSettings.fromJson({'voice': 'unknown'}).voice, 'default');
      expect(const AppSettings().voice, 'default');
    });

    test('每种声线有语速与音调参数', () {
      for (final id in SpeechService.voiceLabels.keys) {
        final params = SpeechService.voices[id];
        expect(params, isNotNull, reason: '$id 缺少参数');
        expect(params!.rate, greaterThan(0));
        expect(params.pitch, greaterThan(0));
      }
    });
  });
}
