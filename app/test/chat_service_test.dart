import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:momopet/models/chat.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';
import 'package:momopet/services/chat/chat_service.dart';
import 'package:momopet/services/chat/local_brain.dart';
import 'package:momopet/services/chat/openai_backend.dart';

Pet _pet() => Pet.fromPack(
      {
        'name': '橘子团子',
        'personality': {
          'traits': ['元气', '贪吃'],
          'greeting': '嗨！',
          'catchphrase': '陪你待着',
          'systemPrompt': '你是一只桌面宠物',
        },
        'frames': {'idle': 'idle.png'},
      },
      id: 'momo',
    );

void main() {
  group('LocalBrain', () {
    final brain = LocalBrain(Random(7));

    test('打招呼走问候分支', () {
      final reply = brain.reply('你好呀', _pet());
      expect(reply.text, isNotEmpty);
      expect(reply.mood, isNot(PetMood.angry));
    });

    test('被骂会生气', () {
      final reply = brain.reply('你真讨厌', _pet());
      expect(reply.mood, PetMood.angry);
    });

    test('摸头会开心或黏人', () {
      final reply = brain.reply('摸摸头', _pet(), affection: 30);
      expect([PetMood.happy, PetMood.love], contains(reply.mood));
    });

    test('空输入不崩', () {
      expect(brain.reply('   ', _pet()).text, isNotEmpty);
    });
  });

  group('OpenAiBackend.parseReply', () {
    test('解析情绪标签', () {
      final reply = OpenAiBackend.parseReply('[love]主人回来啦');
      expect(reply.text, '主人回来啦');
      expect(reply.mood, PetMood.love);
    });

    test('中文方括号也认', () {
      final reply = OpenAiBackend.parseReply('【sleepy】困了…');
      expect(reply.text, '困了…');
      expect(reply.mood, PetMood.sleepy);
    });

    test('没有标签时按内容猜情绪', () {
      expect(OpenAiBackend.parseReply('晚安，做个好梦').mood, PetMood.sleepy);
      expect(OpenAiBackend.parseReply('今天好开心呀').mood, PetMood.happy);
    });
  });

  group('ChatService', () {
    test('在线模型返回 200 时采用其回复', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/chat/completions');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['stream'], false);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '[happy]我在呢！'},
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = ChatService(backend: OpenAiBackend(client: client));
      final result = await service.send(
        input: '在吗',
        pet: _pet(),
        history: const [],
        settings: const AppSettings(chatBackend: ChatBackendKind.openai, baseUrl: 'http://x/v1'),
      );

      expect(result.degraded, isFalse);
      expect(result.reply.text, '我在呢！');
      expect(result.reply.mood, PetMood.happy);
    });

    test('在线模型报错时降级到本地小脑', () async {
      final client = MockClient((request) async => http.Response('boom', 500));
      final service = ChatService(backend: OpenAiBackend(client: client));

      final result = await service.send(
        input: '你好',
        pet: _pet(),
        history: const <ChatMessage>[],
        settings: const AppSettings(chatBackend: ChatBackendKind.openai, baseUrl: 'http://x/v1'),
      );

      expect(result.degraded, isTrue);
      expect(result.error, contains('500'));
      expect(result.reply.text, isNotEmpty);
    });

    test('本地模式不碰网络', () async {
      final service = ChatService();
      final result = await service.send(
        input: '讲个笑话',
        pet: _pet(),
        history: const [],
        settings: const AppSettings(),
      );
      expect(result.degraded, isFalse);
      expect(result.reply.text, isNotEmpty);
    });
  });
}
