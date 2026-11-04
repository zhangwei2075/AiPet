import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat.dart';
import '../../models/pet.dart';
import '../../models/settings.dart';

/// 任意 OpenAI 兼容接口（OpenAI / DeepSeek / Ollama / LM Studio / vLLM…）
class OpenAiBackend {
  OpenAiBackend({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<PetReply> reply({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    String memory = '',
  }) async {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const ChatException('还没有填写 API 地址');
    final uri = Uri.parse('$base/chat/completions');

    final messages = _buildMessages(input: input, pet: pet, history: history, memory: memory);

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (settings.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiKey.trim()}',
          },
          body: jsonEncode({
            'model': settings.model,
            'messages': messages,
            'temperature': 0.85,
            'max_tokens': 220,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode >= 400) {
      final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw ChatException('AI 服务返回 ${response.statusCode}：${detail.length > 160 ? detail.substring(0, 160) : detail}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    final content = (choices?.firstOrNull as Map?)?['message']?['content']?.toString();
    if (content == null || content.trim().isEmpty) {
      throw const ChatException('AI 返回了空消息');
    }
    return parseReply(content.trim());
  }

  /// 流式回复：按 SSE 逐段吐字，调用方自己拼最终文本。
  Stream<String> streamReply({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    String memory = '',
  }) async* {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const ChatException('还没有填写 API 地址');
    final uri = Uri.parse('$base/chat/completions');

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': settings.model,
        'messages': _buildMessages(input: input, pet: pet, history: history, memory: memory),
        'temperature': 0.85,
        'max_tokens': 220,
        'stream': true,
      });
    if (settings.apiKey.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${settings.apiKey.trim()}';
    }

    final response = await _client.send(request).timeout(const Duration(seconds: 25));
    if (response.statusCode >= 400) {
      final detail = await response.stream.bytesToString();
      throw ChatException('AI 服务返回 ${response.statusCode}：${detail.length > 160 ? detail.substring(0, 160) : detail}');
    }

    var received = false;
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 30));
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;
      Map<String, dynamic> data;
      try {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue; // 心跳 / 不完整行，跳过
      }
      final choices = data['choices'] as List?;
      final delta = (choices?.firstOrNull as Map?)?['delta']?['content']?.toString();
      if (delta != null && delta.isNotEmpty) {
        received = true;
        yield delta;
      }
    }
    if (!received) throw const ChatException('AI 返回了空消息');
  }

  List<Map<String, String>> _buildMessages({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    String memory = '',
  }) {
    final system = memory.trim().isEmpty
        ? pet.personality.systemPrompt
        : '${pet.personality.systemPrompt}\n\n你还记得这些（自然地体现在语气里，不要逐条复述）：\n$memory';
    return [
      {'role': 'system', 'content': system},
      ...history.takeLast(10).map(
            (message) => {
              'role': message.role == ChatRole.user ? 'user' : 'assistant',
              'content': message.text,
            },
          ),
      {'role': 'user', 'content': input},
    ];
  }

  static PetReply parseReply(String raw) {
    final match = RegExp(r'^\s*[\[【]\s*(happy|love|angry|sleepy|idle|talk)\s*[\]】]\s*', caseSensitive: false)
        .firstMatch(raw);
    if (match != null) {
      final mood = PetMoodParsing.fromKey(match.group(1)!.toLowerCase());
      final text = raw.substring(match.end).trim();
      return PetReply(text.isEmpty ? '…' : text, mood);
    }
    return PetReply(raw, _guessMood(raw));
  }

  static PetMood _guessMood(String text) {
    if (RegExp(r'[❤♥😻💕]|喜欢|爱').hasMatch(text)) return PetMood.love;
    if (RegExp(r'[😠😤]|哼|讨厌|生气').hasMatch(text)) return PetMood.angry;
    if (RegExp(r'[😴💤]|困|睡|晚安').hasMatch(text)) return PetMood.sleepy;
    if (RegExp(r'[😊😄✧]|哈哈|开心|好耶').hasMatch(text)) return PetMood.happy;
    return PetMood.talk;
  }
}

class ChatException implements Exception {
  const ChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _TakeLast<T> on List<T> {
  Iterable<T> takeLast(int count) => length <= count ? this : sublist(length - count);
}
