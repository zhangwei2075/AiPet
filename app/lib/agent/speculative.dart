import 'dart:async';

import 'package:flutter/foundation.dart';

import 'brain_host.dart';
import 'triggers/quiet_hours.dart';
import 'task_store.dart';

/// 投机执行（Super-agent 五大机制之一）的宠物版：预判式关怀。
///
/// 与「主动搭话」的区别：主动搭话是随机性格词库，投机执行是**基于环境线索**
/// 提前拟一句更贴切的关怀草稿（下班时间快到、日程临近），缓存起来等合适时机输出。
/// 不做任何有副作用的事（不发消息、不改文件），只是预生成文本。
///
/// 约束（设计稿 §3/§6，M5 放宽）：
/// · 只有在线模型可用时才生成（离线不浪费规则词库）；
/// · 静默时段不生成、不输出（M5 默认没有静默时段，可在 QuietHours 里配回）；
/// · 每天最多 [maxDraftsPerDay] 条（M5 从 3 提到 12）；
/// · 草稿是「建议」，由 Brain 决定是否/何时汇报。
class SpeculativeEngine {
  SpeculativeEngine({
    required BrainHost host,
    required TaskStore store,
    QuietPolicy? policy,
    DateTime Function()? now,
    Future<String> Function(String prompt)? generator,
  })  : _host = host,
        _store = store,
        _policy = policy ?? QuietPolicy(),
        _now = now ?? DateTime.now,
        _generator = generator ?? _defaultGenerator;

  final BrainHost _host;
  final TaskStore _store;
  final QuietPolicy _policy;
  final DateTime Function() _now;
  final Future<String> Function(String prompt) _generator;

  static const int maxDraftsPerDay = 12;

  final List<SpeculativeDraft> _drafts = [];
  String _draftDay = '';

  List<SpeculativeDraft> get drafts => List.unmodifiable(_drafts);

  /// 由 Brain 的 tick 调用：检查是否有值得预判的线索，生成草稿。
  Future<void> consider() async {
    if (!_host.agentOnlineAvailable) return;
    final now = _now();
    if (_policy.isQuiet(now)) return;
    final day = '${now.year}-${now.month}-${now.day}';
    if (day != _draftDay) {
      _draftDay = day;
      _drafts.clear();
    }
    if (_drafts.length >= maxDraftsPerDay) return;

    final prompt = _pickPrompt(now);
    if (prompt == null || _drafts.any((d) => d.prompt == prompt)) return;
    if (!_policy.allow('speculative', at: now)) return;

    try {
      final text = await _generator(prompt).timeout(const Duration(seconds: 12));
      if (text.trim().isEmpty) return;
      _drafts.add(SpeculativeDraft(
        id: 'draft-${now.microsecondsSinceEpoch}',
        prompt: prompt,
        text: text.trim(),
        createdAt: now,
      ));
      debugPrint('[speculative] 草稿已生成: $prompt');
    } catch (error) {
      debugPrint('[speculative] 生成失败（静默忽略）: $error');
    }
  }

  /// 取出一条可输出的草稿并消费掉；没有返回 null。
  SpeculativeDraft? takeDraft({String? category}) {
    if (_drafts.isEmpty) return null;
    final index = category == null
        ? 0
        : _drafts.indexWhere((d) => d.category == category);
    if (index < 0) return null;
    final now = _now();
    if (_policy.isQuiet(now)) return null;
    return _drafts.removeAt(index);
  }

  /// 线索 → 提示词。全确定性，不调模型。
  String? _pickPrompt(DateTime now) {
    final hour = now.hour + now.minute / 60;
    // 下班前半小时：主人快回来了
    if (hour >= 17.5 && hour < 18.0) return '主人快下班了，预一句迎接的话';
    // 睡前时段：温柔道晚安
    if (hour >= 21.0 && hour < 22.0) return '该提醒主人早点休息了，预一句晚安';
    // 临近待办：从任务表里找最近的一次
    return null;
  }

  /// 接近的日程任务（30 分钟内）也值得预判。
  Future<bool> hasUpcomingTask() async {
    final now = _now();
    final soon = now.add(const Duration(minutes: 30));
    final tasks = await _store.load();
    return tasks.any((t) => t.isScheduled && !t.at.isBefore(now) && !t.at.isAfter(soon));
  }

  /// 由 Brain 在收到 Trigger 事件时调用：有草稿就吐一句，没有就沉默。
  Future<SpeculativeDraft?> considerOutput() async {
    if (await hasUpcomingTask()) {
      final draft = takeDraft(category: 'schedule');
      if (draft != null) return draft;
    }
    return takeDraft();
  }

  static Future<String> _defaultGenerator(String prompt) async {
    // 实际生成由 Brain 注入（复用 chat 后端），这里给降级文案保证离线不崩。
    return switch (prompt) {
      '主人快下班了，预一句迎接的话' => '主人快回来了，我等你哦！',
      '该提醒主人早点休息了，预一句晚安' => '早点睡吧，明天见。',
      _ => '主人，忙完了吗？',
    };
  }
}

@immutable
class SpeculativeDraft {
  const SpeculativeDraft({
    required this.id,
    required this.prompt,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String prompt;
  final String text;
  final DateTime createdAt;

  String get category => prompt.contains('下班') ? 'home' : prompt.contains('休息') ? 'sleep' : 'other';
}
