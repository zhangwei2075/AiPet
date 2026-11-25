import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/settings.dart';
import 'episodic_event.dart';

/// 日结摘要（docs/m2-memory-plan.md §4-④）。
///
/// · 在线：独立小请求让模型把当天事件压成日记式摘要（失败返回 null）；
/// · 离线/失败：模板拼接兜底，事实不丢。
class DigestGenerator {
  DigestGenerator({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _kindLabel = {
    EpisodeKind.chat: '主人聊到',
    EpisodeKind.task: '任务',
    EpisodeKind.interaction: '互动',
    EpisodeKind.digest: '摘要',
  };

  /// 模板兜底：按类型分组拼接，≤150 字。
  String templateDigest(List<EpisodicEvent> dayEvents) {
    if (dayEvents.isEmpty) return '';
    final byKind = <EpisodeKind, List<String>>{};
    for (final event in dayEvents) {
      byKind.putIfAbsent(event.kind, () => []).add(event.content);
    }
    final parts = <String>[];
    for (final entry in byKind.entries) {
      final label = _kindLabel[entry.key] ?? entry.key.name;
      final joined = entry.value.take(4).join('；');
      parts.add('$label：$joined');
    }
    var text = parts.join('。');
    if (text.length > 150) text = '${text.substring(0, 148)}…';
    return text;
  }

  /// 在线摘要：失败/超时返回 null（调用方回退模板）。
  Future<String?> llmDigest({
    required List<EpisodicEvent> dayEvents,
    required AppSettings settings,
  }) async {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || dayEvents.isEmpty) return null;
    try {
      final facts = dayEvents.take(40).map((e) => '· ${e.content}').join('\n');
      final response = await _client
          .post(
            Uri.parse('$base/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              if (settings.apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${settings.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': settings.model,
              'messages': [
                {
                  'role': 'system',
                  'content': '你是桌面宠物的记忆管理员。把主人一天的事实压缩成一段'
                      '不超过 120 字的日记式摘要，只保留有信息量的内容，直接输出摘要正文。',
                },
                {'role': 'user', 'content': facts},
              ],
              'temperature': 0.3,
              'max_tokens': 160,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content = ((data['choices'] as List?)?.firstOrNull as Map?)?['message']?['content'];
      final text = content?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      return text.length > 150 ? text.substring(0, 148) : text;
    } catch (_) {
      return null;
    }
  }
}
