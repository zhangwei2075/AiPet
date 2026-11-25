import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次工具调用的留痕。
///
/// 全权限不等于无痕迹：每次调用都记「谁、什么时候、调了什么、参数摘要、
/// 成功与否、输出摘要、耗时」。参数与输出都做截断与敏感字段打码，
/// 审计本身不成为第二份隐私副本。
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.tool,
    required this.source,
    required this.argsSummary,
    required this.ok,
    required this.outputSummary,
    required this.elapsedMs,
  });

  final String id;
  final DateTime at;
  final String tool;

  /// 触发来源：user（聊天指令）/ goal（自主目标）/ trigger（感知事件）/ mcp。
  final String source;
  final String argsSummary;
  final bool ok;
  final String outputSummary;
  final int elapsedMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'tool': tool,
        'source': source,
        'argsSummary': argsSummary,
        'ok': ok,
        'outputSummary': outputSummary,
        'elapsedMs': elapsedMs,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id']?.toString() ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        tool: json['tool']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        argsSummary: json['argsSummary']?.toString() ?? '',
        ok: json['ok'] == true,
        outputSummary: json['outputSummary']?.toString() ?? '',
        elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      );

  String get timeLabel =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}:'
      '${at.second.toString().padLeft(2, '0')}';
}

/// 敏感键：命中就把值换成 `***`，避免把 Key / 口令写进审计。
const _sensitiveKeys = {
  'apikey', 'api_key', 'key', 'token', 'password', 'passwd', 'secret',
  'authorization', 'auth', 'cookie', 'credential',
};

/// 参数摘要：稳定 JSON + 打码 + 截断。纯函数，便于单测。
String summarizeArgs(Map<String, dynamic> args, {int limit = 400}) {
  final sanitized = <String, dynamic>{};
  args.forEach((key, value) {
    final lowered = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    sanitized[key] = _sensitiveKeys.contains(lowered) ? '***' : value;
  });
  var text = const JsonEncoder.withIndent(' ').convert(sanitized).replaceAll('\n', ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return truncate(text, limit);
}

String truncate(String text, int limit) =>
    text.length <= limit ? text : '${text.substring(0, limit)}…（已截断）';

/// 滚动审计日志：shared_preferences 里保留最近 [capacity] 条。
class AuditLog {
  AuditLog({SharedPreferences? prefs, String key = prefsKey, this.capacity = 500})
      : _prefs = prefs,
        _key = key;

  static const String prefsKey = 'agent.audit.v1';

  SharedPreferences? _prefs;
  final String _key;
  final int capacity;

  Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<AuditEntry>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          AuditEntry.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> record({
    required String tool,
    required Map<String, dynamic> args,
    required bool ok,
    required String output,
    required int elapsedMs,
    String source = 'user',
    DateTime? at,
  }) async {
    final entries = List<AuditEntry>.of(await load());
    entries.add(AuditEntry(
      id: 'audit-${(at ?? DateTime.now()).microsecondsSinceEpoch}',
      at: at ?? DateTime.now(),
      tool: tool,
      source: source,
      argsSummary: summarizeArgs(args),
      ok: ok,
      outputSummary: truncate(output.replaceAll(RegExp(r'\s+'), ' ').trim(), 500),
      elapsedMs: elapsedMs,
    ));
    final keep = entries.length > capacity ? entries.sublist(entries.length - capacity) : entries;
    await _save(keep);
  }

  /// 最近 [limit] 条，按时间倒序；传 [day] 则只看那一天。
  Future<List<AuditEntry>> recent({int limit = 100, DateTime? day}) async {
    var entries = await load();
    if (day != null) {
      entries = entries
          .where((e) =>
              e.at.year == day.year && e.at.month == day.month && e.at.day == day.day)
          .toList();
    }
    final sorted = [...entries]..sort((a, b) => b.at.compareTo(a.at));
    return sorted.length <= limit ? sorted : sorted.sublist(0, limit);
  }

  Future<void> clear() => _save(const []);

  Future<void> _save(List<AuditEntry> entries) async {
    final prefs = await _instance();
    await prefs.setString(_key, jsonEncode([for (final e in entries) e.toJson()]));
  }
}
