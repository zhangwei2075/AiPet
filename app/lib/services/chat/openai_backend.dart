import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat.dart';
import '../../models/pet.dart';
import '../../models/settings.dart';

/// 任意 OpenAI 兼容接口（OpenAI / DeepSeek / Ollama / LM Studio / vLLM…），
/// 以及 Anthropic 兼容接口（阿里云百炼 / GLM / Kimi 的 Coding Plan）。
/// 由 [AppSettings.apiProtocol] 选择协议，地址 / 模型 / Key 复用同一组配置。
class OpenAiBackend {
  OpenAiBackend({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  bool _isAnthropic(AppSettings settings) => settings.apiProtocol == 'anthropic';

  Future<PetReply> reply({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    String memory = '',
    String systemPreamble = '',
  }) async {
    if (_isAnthropic(settings)) {
      return _replyAnthropic(input: input, pet: pet, history: history, settings: settings, memory: memory, systemPreamble: systemPreamble);
    }
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const ChatException('还没有填写 API 地址');
    final uri = Uri.parse('$base/chat/completions');

    final messages = _buildMessages(input: input, pet: pet, history: history, memory: memory, systemPreamble: systemPreamble);

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (settings.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiKey.trim()}',
            if (settings.isOpencodeGateway) 'x-opencode-session': settings.opencodeSessionId,
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
    String systemPreamble = '',
  }) async* {
    if (_isAnthropic(settings)) {
      yield* _streamAnthropic(input: input, pet: pet, history: history, settings: settings, memory: memory, systemPreamble: systemPreamble);
      return;
    }
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const ChatException('还没有填写 API 地址');
    final uri = Uri.parse('$base/chat/completions');

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': settings.model,
        'messages': _buildMessages(input: input, pet: pet, history: history, memory: memory, systemPreamble: systemPreamble),
        'temperature': 0.85,
        'max_tokens': 220,
        'stream': true,
      });
    if (settings.apiKey.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${settings.apiKey.trim()}';
    }
    if (settings.isOpencodeGateway) {
      request.headers['x-opencode-session'] = settings.opencodeSessionId;
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

  // ---------- Anthropic 兼容协议（/messages） ----------

  Future<PetReply> _replyAnthropic({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    String memory = '',
    String systemPreamble = '',
  }) async {
    final uri = _anthropicUri(settings);
    final parts = _splitSystem(input: input, pet: pet, history: history, memory: memory, systemPreamble: systemPreamble);

    final response = await _client
        .post(
          uri,
          headers: _anthropicHeaders(settings),
          body: jsonEncode({
            'model': settings.model,
            'max_tokens': 220,
            if (parts.system.isNotEmpty) 'system': parts.system,
            'messages': parts.messages,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode >= 400) {
      final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw ChatException('AI 服务返回 ${response.statusCode}：${detail.length > 160 ? detail.substring(0, 160) : detail}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = data['content'] as List?;
    final text = content
        ?.whereType<Map>()
        .where((block) => (block['type']?.toString() ?? 'text') == 'text')
        .map((block) => block['text']?.toString() ?? '')
        .join()
        .trim();
    if (text == null || text.isEmpty) {
      throw const ChatException('AI 返回了空消息');
    }
    return parseReply(text);
  }

  Stream<String> _streamAnthropic({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    String memory = '',
    String systemPreamble = '',
  }) async* {
    final uri = _anthropicUri(settings);
    final parts = _splitSystem(input: input, pet: pet, history: history, memory: memory, systemPreamble: systemPreamble);

    final request = http.Request('POST', uri)
      ..headers.addAll(_anthropicHeaders(settings))
      ..body = jsonEncode({
        'model': settings.model,
        'max_tokens': 220,
        if (parts.system.isNotEmpty) 'system': parts.system,
        'messages': parts.messages,
        'stream': true,
      });

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
      Map<String, dynamic> data;
      try {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (data['type'] != 'content_block_delta') continue;
      final delta = data['delta'] as Map?;
      final text = delta?['text']?.toString();
      if (text != null && text.isNotEmpty) {
        received = true;
        yield text;
      }
    }
    if (!received) throw const ChatException('AI 返回了空消息');
  }

  Uri _anthropicUri(AppSettings settings) {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const ChatException('还没有填写 API 地址');
    // Anthropic 协议路径固定为 {base}/messages（base 一般以 /v1 结尾）。
    return Uri.parse('$base/messages');
  }

  Map<String, String> _anthropicHeaders(AppSettings settings) => {
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        // OpenCode Console 的 Key 在所有协议下都走 Bearer（官方 harness 文档）；
        // 原生 Anthropic 则要求 x-api-key。两个都带可兼容两边，服务端各取所需。
        if (settings.apiKey.trim().isNotEmpty) ...{
          'x-api-key': settings.apiKey.trim(),
          if (settings.isOpencodeGateway) 'Authorization': 'Bearer ${settings.apiKey.trim()}',
        },
        if (settings.isOpencodeGateway) 'x-opencode-session': settings.opencodeSessionId,
      };

  /// Anthropic 协议的 system 是独立字段，消息列表只含 user/assistant。
  ({String system, List<Map<String, String>> messages}) _splitSystem({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    String memory = '',
    String systemPreamble = '',
  }) {
    final all = _buildMessages(input: input, pet: pet, history: history, memory: memory, systemPreamble: systemPreamble);
    final system = (all.isNotEmpty && all.first['role'] == 'system') ? (all.first['content'] ?? '') : '';
    final messages = all.where((message) => message['role'] != 'system').toList();
    return (system: system, messages: messages);
  }

  List<Map<String, String>> _buildMessages({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    String memory = '',
    String systemPreamble = '',
  }) {
    // 高权限身份说明放在最前面，且明确覆盖人格提示词里的「只聊天」限制；
    // 由 ChatCoordinator 用 buildAgentPreamble / buildAgentSystemPrompt 生成。
    final persona = pet.personality.systemPrompt;
    final system = '$systemPreamble'
        '${memory.trim().isEmpty ? persona : '$persona\n\n你还记得这些（自然地体现在语气里，不要逐条复述）：\n$memory'}';
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
