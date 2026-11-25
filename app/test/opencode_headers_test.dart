import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';
import 'package:momopet/services/chat/openai_backend.dart';

Pet _pet() => Pet.fromPack(
      {
        'name': '有财',
        'personality': {
          'traits': ['元气'],
          'greeting': '嗨！',
          'catchphrase': '陪你待着',
          'systemPrompt': '你是一只桌面宠物',
        },
        'frames': {'idle': 'idle.png'},
      },
      id: 'youcai',
    );

void main() {
  group('OpenCode Go 请求头', () {
    test('OpenAI 协议带会话头 + Bearer，打到 /inference/go/openai/v1', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '[happy]你好呀'}}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final settings = AppSettings(
        chatBackend: ChatBackendKind.openai,
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        apiKey: 'oc_sk_test',
        model: 'deepseek-v4.1-flash',
      );
      final reply = await OpenAiBackend(client: client).reply(
        input: '你好',
        pet: _pet(),
        history: const [],
        settings: settings,
      );

      expect(reply.text, '你好呀');
      expect(captured!.url.path, '/inference/go/openai/v1/chat/completions');
      expect(captured!.headers['Authorization'], 'Bearer oc_sk_test');
      expect(captured!.headers['x-opencode-session'], settings.opencodeSessionId);
    });

    test('非 OpenCode 网关不发会话头', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '你好'}}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await OpenAiBackend(client: client).reply(
        input: '你好',
        pet: _pet(),
        history: const [],
        settings: const AppSettings(
          chatBackend: ChatBackendKind.openai,
          baseUrl: 'https://api.deepseek.com',
          apiKey: 'sk-test',
          model: 'deepseek-v4-flash',
        ),
      );

      expect(captured!.headers.containsKey('x-opencode-session'), isFalse);
      expect(captured!.headers['Authorization'], 'Bearer sk-test');
    });

    test('Anthropic 协议带会话头 + 双认证头，打到 /anthropic/v1/messages', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': '[talk]我在这儿'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final settings = AppSettings(
        chatBackend: ChatBackendKind.openai,
        apiProtocol: 'anthropic',
        baseUrl: 'https://opencode.ai/inference/go/anthropic/v1',
        apiKey: 'oc_sk_test',
        model: 'claude-sonnet-4-6',
      );
      final reply = await OpenAiBackend(client: client).reply(
        input: '在吗',
        pet: _pet(),
        history: const [],
        settings: settings,
      );

      expect(reply.text, '我在这儿');
      expect(captured!.url.path, '/inference/go/anthropic/v1/messages');
      expect(captured!.headers['x-api-key'], 'oc_sk_test');
      expect(captured!.headers['Authorization'], 'Bearer oc_sk_test');
      expect(captured!.headers['x-opencode-session'], settings.opencodeSessionId);
      expect(captured!.headers['anthropic-version'], '2023-06-01');
    });

    test('流式请求也带会话头', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode('data: {"choices":[{"delta":{"content":"好"}}]}\n\ndata: [DONE]\n\n'),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final settings = AppSettings(
        chatBackend: ChatBackendKind.openai,
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        apiKey: 'oc_sk_test',
        model: 'deepseek-v4.1-flash',
      );
      final parts = await OpenAiBackend(client: client)
          .streamReply(input: '你好', pet: _pet(), history: const [], settings: settings)
          .toList();

      expect(parts, ['好']);
      expect(captured!.headers['x-opencode-session'], settings.opencodeSessionId);
    });
  });
}
