import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';
import 'package:momopet/services/chat/chat_service.dart';
import 'package:momopet/services/chat/openai_backend.dart';
import 'package:momopet/services/speech_service.dart';

Pet _pet() => Pet.fromPack(
      {
        'name': '小黄豆',
        'personality': {'systemPrompt': '你是一只名叫小黄豆的桌面宠物', 'traits': ['憨厚']},
        'frames': {'idle': 'idle.png'},
      },
      id: 'doudou',
    );

const _settings = AppSettings(chatBackend: ChatBackendKind.openai, baseUrl: 'http://x/v1');

void main() {
  group('OpenAiBackend.streamReply', () {
    test('逐段吐出 SSE 增量', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['stream'], isTrue);
        expect(body['model'], _settings.model);
        const sse = 'data: {"choices":[{"delta":{"content":"汪"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":"！"}}]}\n\n'
            'data: {"choices":[{"delta":{}}]}\n\n'
            'data: [DONE]\n\n';
        return http.Response(sse, 200, headers: {'content-type': 'text/event-stream; charset=utf-8'});
      });

      final backend = OpenAiBackend(client: client);
      final chunks = await backend
          .streamReply(input: '在吗', pet: _pet(), history: const [], settings: _settings)
          .toList();

      expect(chunks, ['汪', '！']);
    });

    test('HTTP 错误抛 ChatException', () async {
      final client = MockClient((request) async => http.Response('boom', 500));
      final backend = OpenAiBackend(client: client);

      expect(
        backend.streamReply(input: '在吗', pet: _pet(), history: const [], settings: _settings).toList(),
        throwsA(isA<ChatException>()),
      );
    });

    test('一条内容都没给时抛异常', () async {
      final client = MockClient(
        (request) async => http.Response('data: {"choices":[{"delta":{}}]}\n\ndata: [DONE]\n\n', 200),
      );
      final backend = OpenAiBackend(client: client);

      expect(
        backend.streamReply(input: '在吗', pet: _pet(), history: const [], settings: _settings).toList(),
        throwsA(isA<ChatException>()),
      );
    });

    test('本地模式一次性给完，不走网络', () async {
      final service = ChatService();
      final chunks = await service
          .sendStream(input: '你好', pet: _pet(), history: const [], settings: const AppSettings())
          .toList();
      expect(chunks.length, 1);
      expect(chunks.single, isNotEmpty);
    });

    test('流式文本能被 parseReply 还原情绪', () {
      final reply = OpenAiBackend.parseReply('[sleepy]汪……晚安');
      expect(reply.text, '汪……晚安');
      expect(reply.mood, PetMood.sleepy);
    });
  });

  group('SpeechService.cleanForSpeech', () {
    test('去掉情绪标签、颜文字与 markdown', () {
      final text = SpeechService.cleanForSpeech('[happy] 汪！🐶 **好开心**');
      expect(text, isNot(contains('[happy]')));
      expect(text, isNot(contains('🐶')));
      expect(text, isNot(contains('*')));
      expect(text, contains('汪'));
    });

    test('中文方括号标签也认', () {
      expect(SpeechService.cleanForSpeech('【sleepy】困了…'), '困了…');
    });

    test('超长文本截断', () {
      final text = SpeechService.cleanForSpeech('好' * 200);
      expect(text.length, lessThanOrEqualTo(91));
    });

    test('空文本直接返回空', () {
      expect(SpeechService.cleanForSpeech('   '), isEmpty);
    });
  });
}
