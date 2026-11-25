import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/settings.dart';
import 'digest.dart';
import 'episodic_event.dart';
import 'episodic_store.dart';
import 'extractor.dart';
import 'retrieval.dart';

/// 记忆页按天视图。
@immutable
class MemoryDayView {
  const MemoryDayView(this.day, this.digest, this.events);

  final String day;
  final String? digest;
  final List<EpisodicEvent> events;
}

/// 情景记忆门面：写入管道（三源）/ 跨天日结 / 上下文组装 / UI 视图。
///
/// 只对两个调用点负责：
/// · `assemble()` 替换 chat_coordinator 里原来的 `memory.promptFor(pet.id)`；
/// · 各 `record*` 由聊天流 / PetBehavior / Brain 在事件发生处调用。
class MemoryService {
  MemoryService({
    required EpisodicStore store,
    FactExtractor extractor = const FactExtractor(),
    DigestGenerator? digestGenerator,
    http.Client? client,
    DateTime Function()? now,
  })  : _store = store,
        _extractor = extractor,
        _digestGenerator = digestGenerator ?? DigestGenerator(client: client),
        _now = now ?? DateTime.now;

  final EpisodicStore _store;
  final FactExtractor _extractor;
  final DigestGenerator _digestGenerator;
  final DateTime Function() _now;

  static const _toggleKey = 'aipet.memory.extraction.enabled';
  static const _assembleBudget = 2000;

  final http.Client _client = http.Client();
  bool _loaded = false;
  bool? _extractionEnabled;

  /// 每日互动计数：'$petId|$day|$label' → n（互动降噪：一天一条汇总）。
  final Map<String, int> _interactionCounts = {};

  // ---------------------------------------------------------------- 生命周期

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _store.load();
    try {
      final prefs = await SharedPreferences.getInstance();
      _extractionEnabled = prefs.getBool(_toggleKey) ?? true;
    } catch (_) {
      _extractionEnabled = true;
    }
  }

  bool get extractionEnabled => _extractionEnabled ?? true;

  Future<void> setExtractionEnabled(bool value) async {
    _extractionEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_toggleKey, value);
    } catch (_) {}
  }

  Future<void> flush() => _store.flush();

  void dispose() {
    _store.dispose();
    _client.close();
  }

  // ---------------------------------------------------------------- 写入管道

  /// 聊天事实：规则抽取必做；规则没抽到且在线时，让模型补抽一次（抓漏）。
  Future<void> recordFromChat({
    required String petId,
    required String userText,
    AppSettings? settings,
  }) async {
    if (!extractionEnabled) return;
    final now = _now();
    var recorded = 0;
    for (final fact in _extractor.extract(userText, now)) {
      _store.add(EpisodicEvent(
        id: '${now.millisecondsSinceEpoch}-c$recorded',
        petId: petId,
        at: now,
        kind: EpisodeKind.chat,
        content: fact.content,
        importance: fact.importance,
        tag: fact.tag,
      ));
      recorded++;
    }
    if (recorded > 0 || settings == null || !settings.onlineAvailable) return;
    // 抓漏模式：规则没命中才问模型，避免每句话都多打一次。
    final extra = await _llmExtract(userText, settings);
    for (var i = 0; i < extra.length; i++) {
      _store.add(EpisodicEvent(
        id: '${now.millisecondsSinceEpoch}-l$i',
        petId: petId,
        at: _now(),
        kind: EpisodeKind.chat,
        content: extra[i],
        importance: 2,
      ));
    }
  }

  /// 日结已尝试过的标记：LLM 失败时不每 20 秒重打一次。
  final Set<String> _rollAttempts = {};

  /// 互动事件：同 tag 当天一条汇总（「今天被摸了 23 次」）。
  void recordInteraction(String petId, String label, {int amount = 1}) {
    if (petId.isEmpty || !extractionEnabled) return;
    final now = _now();
    final day = dayKeyOf(now);
    final key = '$petId|$day|$label';
    final count = (_interactionCounts[key] ?? 0) + amount;
    _interactionCounts[key] = count;
    _store.upsertByTag(EpisodicEvent(
      id: key,
      petId: petId,
      at: now,
      kind: EpisodeKind.interaction,
      content: '今天$label$count 次',
      importance: 1,
      tag: '互动·$label',
    ));
  }

  /// 任务结果（提醒创建等）。
  void recordTask(String petId, String fact, {String? tag}) {
    if (!extractionEnabled) return;
    final now = _now();
    _store.add(EpisodicEvent(
      id: '${now.millisecondsSinceEpoch}-t',
      petId: petId,
      at: now,
      kind: EpisodeKind.task,
      content: fact,
      importance: 2,
      tag: tag ?? '提醒',
    ));
  }

  // ---------------------------------------------------------------- 跨天日结

  /// 给「昨天之前、还没摘要」的日子生成 digest。挂在 Brain 心跳上，
  /// 每天只会真正跑一次（有 digest 的日子直接跳过）。
  Future<void> dailyRollIfNeeded(String petId, {AppSettings? settings}) async {
    if (petId.isEmpty) return;
    final today = dayKeyOf(_now());
    final days = _store.daysOf(petId);
    final pending = days.where((day) => day.compareTo(today) < 0).toList()
      ..sort((a, b) => b.compareTo(a)); // 最新优先
    for (final day in pending) {
      if (_store.hasDigest(petId, day)) continue;
      final attemptKey = '$petId|$day';
      if (!_rollAttempts.add(attemptKey)) continue; // 失败过就不再重试（次日重启重置）
      final events = _store.eventsOn(petId, day);
      if (events.isEmpty) continue;
      var text = _digestGenerator.templateDigest(events);
      // 只对最近一个未摘要的日子尝试在线精摘，控制成本。
      if (identical(day, pending.first) && settings != null && settings.onlineAvailable) {
        final better = await _digestGenerator.llmDigest(dayEvents: events, settings: settings);
        if (better != null) text = better;
      }
      _store.addDigest(petId, day, text);
      await _store.flush();
    }
  }

  // ---------------------------------------------------------------- 组装

  /// 上下文组装（docs/m2-memory-plan.md §6）：
  /// 计数记忆 + 近 3 天 digest + top-K 情景，整体 ≤2000 字符。
  /// 输出内容不带外层引导语——那由 openai_backend 的 system 模板负责。
  String assemble({
    required String petId,
    required String query,
    required String countMemory,
  }) {
    final parts = <String>[];
    final count = countMemory.trim();
    if (count.isNotEmpty) parts.add(count);

    final today = dayKeyOf(_now());
    final digests = _store.digestsOf(petId);
    final recentDays = digests.keys.where((d) => d.compareTo(today) < 0).toList()
      ..sort((a, b) => b.compareTo(a));
    final digestTexts = <String>[
      for (final day in recentDays.take(3))
        if (digests[day]!.trim().isNotEmpty) '（$day）${digests[day]!.trim()}',
    ];
    if (digestTexts.isNotEmpty) {
      parts.add('最近的日子：\n${digestTexts.join('\n')}');
    }

    final episodes = const EpisodeRetrieval()
        .withinBudget(const EpisodeRetrieval().retrieve(
          events: _store
              .eventsOf(petId)
              .where((e) => e.kind != EpisodeKind.digest)
              .toList(growable: false),
          query: query,
          now: _now(),
        ));
    if (episodes.isNotEmpty) {
      parts.add('印象比较深的：\n${[
        for (final episode in episodes) '· ${episode.event.content}',
      ].join('\n')}');
    }

    var text = parts.join('\n\n');
    if (text.length > _assembleBudget) text = text.substring(0, _assembleBudget - 1);
    return text;
  }

  // ---------------------------------------------------------------- UI 视图

  List<MemoryDayView> viewDays(String petId) {
    final pet = _store.rawOf(petId);
    final days = pet.days.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        MemoryDayView(day, pet.digests[day], List.of(pet.days[day] ?? const [])),
    ];
  }

  int eventCount(String petId) => viewDays(petId).fold(0, (sum, d) => sum + d.events.length);

  Future<void> clearDay(String petId, String day) => _store.clearDay(petId, day);

  Future<void> clearAll(String petId) => _store.clearAll(petId);

  // ---------------------------------------------------------------- 内部

  /// 在线抓漏抽取：0~2 条第三人称事实。失败返回空。
  Future<List<String>> _llmExtract(String userText, AppSettings settings) async {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return const [];
    try {
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
                  'content': '从用户这句话里提取值得宠物长期记住的事实，0~2 条，'
                      '输出 JSON 字符串数组，每条以「主人」开头、第三人称、不超过 30 字。'
                      '没有值得记的就输出 []。只输出 JSON。',
                },
                {'role': 'user', 'content': userText},
              ],
              'temperature': 0,
              'max_tokens': 120,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) return const [];
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content = ((data['choices'] as List?)?.firstOrNull as Map?)?['message']?['content'];
      final match = RegExp(r'\[[\s\S]*\]').firstMatch(content?.toString() ?? '');
      if (match == null) return const [];
      final list = jsonDecode(match.group(0)!) as List;
      return [
        for (final item in list)
          if (item.toString().trim().isNotEmpty &&
              item.toString().length <= 40 &&
              !FactExtractor.isSensitive(item.toString()))
            item.toString().trim(),
      ].take(2).toList();
    } catch (_) {
      return const [];
    }
  }
}
