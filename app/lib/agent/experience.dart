import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条「做过一桩事」的经验。
///
/// 与审计日志的区别：审计是逐次工具调用的流水，经验是**目标级复盘**——
/// 记下「这类事该用哪几个工具、走通了没有、下次要注意什么」，
/// 再回灌给聊天与自主规划，形成越用越会的闭环。
@immutable
class Experience {
  const Experience({
    required this.id,
    required this.at,
    required this.goal,
    required this.ok,
    required this.tools,
    required this.summary,
    required this.origin,
  });

  final String id;
  final DateTime at;
  final String goal;
  final bool ok;
  final List<String> tools;
  final String summary;
  final String origin; // goal / chat / self

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'goal': goal,
        'ok': ok,
        'tools': tools,
        'summary': summary,
        'origin': origin,
      };

  factory Experience.fromJson(Map<String, dynamic> json) => Experience(
        id: json['id']?.toString() ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        goal: json['goal']?.toString() ?? '',
        ok: json['ok'] == true,
        tools: [
          for (final item in (json['tools'] as List?) ?? const []) item.toString(),
        ],
        summary: json['summary']?.toString() ?? '',
        origin: json['origin']?.toString() ?? 'goal',
      );

  String get dayLabel =>
      '${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// 把一句话切成检索用的词元：英文按单词，中文按双字滑窗。
/// 纯函数，单测直接覆盖。
List<String> tokenize(String text) {
  final tokens = <String>{};
  final lower = text.toLowerCase();
  for (final match in RegExp(r'[a-z0-9_]+').allMatches(lower)) {
    final word = match.group(0)!;
    if (word.length >= 2) tokens.add(word);
  }
  final han = lower.replaceAll(RegExp(r'[^一-龥]'), ' ');
  for (final segment in han.split(RegExp(r'\s+'))) {
    if (segment.length == 1) {
      tokens.add(segment);
    } else {
      for (var i = 0; i + 1 < segment.length; i++) {
        tokens.add(segment.substring(i, i + 2));
      }
    }
  }
  return tokens.toList(growable: false);
}

/// 相关度：词元 Jaccard 近似 + 成功经验加权 + 时间轻微加权。
double experienceScore(String query, Experience exp) {
  final a = tokenize(query).toSet();
  final b = tokenize(exp.goal).toSet();
  if (a.isEmpty || b.isEmpty) return 0;
  var overlap = 0;
  for (final token in a) {
    if (b.contains(token)) overlap++;
  }
  if (overlap == 0) return 0;
  final ratio = overlap / (a.length < b.length ? a.length : b.length);
  return ratio + (exp.ok ? 0.15 : 0.05);
}

/// 把检索到的经验写成能直接塞进 system / user prompt 的一段。
String lessonsForPrompt(List<Experience> items) {
  if (items.isEmpty) return '';
  return '以往处理类似事情的经验（可参考，不必照抄；工具名以当前清单为准）：\n'
      '${[
        for (final e in items)
          '· ${e.ok ? '成功' : '失败'}「${_clip(e.goal, 42)}」'
              '${e.tools.isEmpty ? '' : ' → 用过 ${e.tools.take(6).join('、')}'}'
              '；结论：${_clip(e.summary, 90)}',
      ].join('\n')}';
}

String _clip(String text, int limit) =>
    text.length <= limit ? text : '${text.substring(0, limit)}…';

String _oneLine(String text, int limit) =>
    _clip(text.replaceAll(RegExp(r'\s+'), ' ').trim(), limit);

/// 经验库：滚动保留最近 [capacity] 条，落在 shared_preferences。
class ExperienceBank {
  ExperienceBank({SharedPreferences? prefs, String key = prefsKey, this.capacity = 200})
      : _prefs = prefs,
        _key = key;

  static const String prefsKey = 'agent.experience.v1';

  SharedPreferences? _prefs;
  final String _key;
  final int capacity;

  Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<Experience>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          Experience.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> record({
    required String goal,
    required bool ok,
    required List<String> tools,
    required String summary,
    String origin = 'goal',
    DateTime? at,
  }) async {
    final time = at ?? DateTime.now();
    final entry = Experience(
      id: 'exp-${time.microsecondsSinceEpoch}',
      at: time,
      goal: _oneLine(goal, 160),
      ok: ok,
      tools: tools.take(12).toList(growable: false),
      summary: _oneLine(summary, 300),
      origin: origin,
    );
    final all = List<Experience>.of(await load())..add(entry);
    final keep = all.length > capacity ? all.sublist(all.length - capacity) : all;
    await _save(keep);
  }

  Future<List<Experience>> recent({int limit = 30}) async {
    final all = [...await load()]..sort((a, b) => b.at.compareTo(a.at));
    return all.length <= limit ? all : all.sublist(0, limit);
  }

  /// 按目标相似度召回，成功经验优先；结果已按相关度降序。
  Future<List<Experience>> recall(String goal, {int limit = 3}) async {
    final all = await load();
    final scored = <(double, Experience)>[
      for (final e in all)
        if (experienceScore(goal, e) > 0) (experienceScore(goal, e), e),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final pair in scored.take(limit)) pair.$2];
  }

  /// 直接给 prompt 用的一段文字；没有相关经验时返回空串。
  Future<String> recallForPrompt(String goal, {int limit = 3}) async =>
      lessonsForPrompt(await recall(goal, limit: limit));

  Future<void> clear() => _save(const []);

  Future<void> _save(List<Experience> entries) async {
    final prefs = await _instance();
    await prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
  }
}
