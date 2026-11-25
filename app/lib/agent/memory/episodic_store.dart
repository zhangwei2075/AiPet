import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'episodic_event.dart';

/// 情景记忆的分区存储（docs/m2-memory-plan.md §5）。
///
/// · 单 key `aipet.episodes.v1`，全内存操作，检索不做 IO；
/// · 写入去抖合并；容量护栏：单日 ≤80 条、单宠物 ≤400 条、digest 留 30 天；
/// · 淘汰顺序：importance 升序，同分取最旧；digest 永不自动淘汰。
class EpisodicStore {
  EpisodicStore({
    SharedPreferences? prefs,
    String key = 'aipet.episodes.v1',
    Duration debounce = const Duration(seconds: 2),
  })  : _prefs = prefs,
        _key = key,
        _debounce = debounce;

  static const String prefsKey = 'aipet.episodes.v1';
  static const int maxPerDay = 80;
  static const int maxPerPet = 400;
  static const int digestKeepDays = 30;

  SharedPreferences? _prefs;
  final String _key;
  final Duration _debounce;

  final Map<String, PetEpisodes> _data = {};
  bool _loaded = false;
  bool _dirty = false;
  Timer? _flushTimer;

  Future<SharedPreferences> _instance() async => _prefs ??= await SharedPreferences.getInstance();

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await _instance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((petId, value) {
        if (value is Map<String, dynamic>) _data[petId] = PetEpisodes.fromJson(value);
      });
    } catch (error) {
      // 记忆坏掉不该影响启动：清空重来。
      debugPrint('[episodes] load failed, reset: $error');
      _data.clear();
    }
  }

  PetEpisodes _of(String petId) => _data[petId] ??= PetEpisodes();

  List<EpisodicEvent> eventsOf(String petId) => [
        for (final day in _of(petId).days.values) ...day,
      ];

  Map<String, String> digestsOf(String petId) => Map.unmodifiable(_of(petId).digests);

  /// 有事件的日子（新→旧）。
  List<String> daysOf(String petId) {
    final days = _of(petId)
        .days
        .entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => entry.key)
        .toList();
    days.sort((a, b) => b.compareTo(a));
    return days;
  }

  List<EpisodicEvent> eventsOn(String petId, String day) =>
      List.unmodifiable(_of(petId).days[day] ?? const []);

  /// UI 视图用的原始分区（只读约定）。
  PetEpisodes rawOf(String petId) => _of(petId);

  bool hasDigest(String petId, String day) => _of(petId).digests.containsKey(day);

  /// 写入一条情景（同日同内容去重），进入去抖队列。
  void add(EpisodicEvent event) {
    final pet = _of(event.petId);
    final day = dayKeyOf(event.at);
    final list = pet.days.putIfAbsent(day, () => <EpisodicEvent>[]);
    if (list.any((e) => e.content == event.content)) return;
    list.add(event);
    _evictDay(list);
    _evictPet(event.petId);
    _scheduleFlush();
  }

  /// 覆盖/更新当天同 tag 的事件（互动降噪：一天一条汇总）。
  void upsertByTag(EpisodicEvent event) {
    final pet = _of(event.petId);
    final day = dayKeyOf(event.at);
    final list = pet.days.putIfAbsent(day, () => <EpisodicEvent>[]);
    final index = list.indexWhere((e) => e.tag != null && e.tag == event.tag);
    if (index >= 0) {
      list[index] = event;
    } else {
      list.add(event);
    }
    _evictDay(list);
    _scheduleFlush();
  }

  void addDigest(String petId, String day, String text) {
    _of(petId).digests[day] = text;
    _evictDigests(petId);
    _scheduleFlush();
  }

  Future<void> clearDay(String petId, String day) async {
    _of(petId).days.remove(day);
    _of(petId).digests.remove(day);
    await flush();
  }

  Future<void> clearAll(String petId) async {
    _data.remove(petId);
    await flush();
  }

  // ---------------------------------------------------------------- 淘汰

  void _evictDay(List<EpisodicEvent> list) {
    while (list.length > maxPerDay) {
      list.remove(_weakest(list));
    }
  }

  void _evictPet(String petId) {
    final pet = _of(petId);
    var total = pet.days.values.fold<int>(0, (sum, list) => sum + list.length);
    while (total > maxPerPet) {
      EpisodicEvent? weakest;
      List<EpisodicEvent>? weakestList;
      for (final list in pet.days.values) {
        final candidate = _weakest(list);
        if (weakest == null ||
            candidate.importance < weakest.importance ||
            (candidate.importance == weakest.importance && candidate.at.isBefore(weakest.at))) {
          weakest = candidate;
          weakestList = list;
        }
      }
      if (weakestList == null || weakest == null) break;
      weakestList.remove(weakest);
      total--;
    }
  }

  void _evictDigests(String petId) {
    final pet = _of(petId);
    if (pet.digests.length <= digestKeepDays) return;
    final keys = pet.digests.keys.toList()..sort();
    while (keys.length > digestKeepDays) {
      pet.digests.remove(keys.removeAt(0));
    }
  }

  EpisodicEvent _weakest(List<EpisodicEvent> list) {
    var weakest = list.first;
    for (final event in list.skip(1)) {
      if (event.importance < weakest.importance ||
          (event.importance == weakest.importance && event.at.isBefore(weakest.at))) {
        weakest = event;
      }
    }
    return weakest;
  }

  // ---------------------------------------------------------------- 落盘

  void _scheduleFlush() {
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(_debounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_dirty) return;
    _dirty = false;
    try {
      final prefs = await _instance();
      await prefs.setString(
        _key,
        jsonEncode({for (final entry in _data.entries) entry.key: entry.value.toJson()}),
      );
    } catch (error) {
      _dirty = true; // 写失败保留脏标记，下次再试
      debugPrint('[episodes] flush failed: $error');
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
