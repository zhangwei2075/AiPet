import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet_memory.dart';

/// 长期记忆的落盘与更新。
///
/// 存储结构：`{ "<petId>": { ...PetMemory } }`，键 `aipet.memory.v1`。
/// 和完整对话分开存，这样清空对话不会把「认识了多久」一起清掉。
class MemoryStore {
  static const _key = 'aipet.memory.v1';
  static const _maxNotes = 12;
  static const _maxTopics = 8;

  final Map<String, PetMemory> _memories = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((petId, value) {
        if (value is Map<String, dynamic>) {
          _memories[petId] = PetMemory.fromJson(value, petId: petId);
        }
      });
    } catch (error) {
      // 记忆坏掉不该影响启动
      // ignore: avoid_print
      print('memory load failed: $error');
    }
  }

  PetMemory of(String petId) {
    final now = DateTime.now();
    return _memories[petId] ??= PetMemory(petId: petId, firstMet: now, lastSeen: now);
  }

  /// 拼接给 system prompt 用的记忆片段。
  String promptFor(String petId) => of(petId).promptSummary;

  /// 被摸了一次。返回这次是否触发了新的里程碑备注。
  Future<String?> tap(String petId, {int amount = 1}) async {
    final memory = of(petId);
    memory.taps += amount;
    memory.lastSeen = DateTime.now();
    String? milestone;
    if (memory.taps == 20 || memory.taps == 50 || memory.taps == 100) {
      milestone = '被主人摸到第 ${memory.taps} 次';
      _addNote(memory, milestone);
    }
    await _persist();
    return milestone;
  }

  /// 聊完一轮：记次数、记话题、必要时写里程碑。
  Future<void> chat(String petId, String userText) async {
    final memory = of(petId);
    memory.chats += 1;
    memory.lastSeen = DateTime.now();
    if (memory.chats == 1) _addNote(memory, '第一次和主人说话');
    _observeTopics(memory, userText);
    await _persist();
  }

  Future<void> note(String petId, String text) async {
    _addNote(of(petId), text);
    await _persist();
  }

  Future<void> clear(String petId) async {
    _memories.remove(petId);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _memories.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString(_key, jsonEncode(map));
    } catch (error) {
      // ignore: avoid_print
      print('memory save failed: $error');
    }
  }

  void _addNote(PetMemory memory, String text) {
    if (memory.notes.contains(text)) return;
    memory.notes.add(text);
    while (memory.notes.length > _maxNotes) {
      memory.notes.removeAt(0);
    }
  }

  /// 极简的话题提取：命中关键词就 +1，够用且不会误报太多。
  void _observeTopics(PetMemory memory, String text) {
    if (text.trim().isEmpty) return;
    for (final topic in _topicPatterns.entries) {
      if (topic.value.hasMatch(text)) {
        memory.topics[topic.key] = (memory.topics[topic.key] ?? 0) + 1;
      }
    }
    while (memory.topics.length > _maxTopics) {
      final weakest = memory.topics.entries.reduce((a, b) => a.value <= b.value ? a : b);
      memory.topics.remove(weakest.key);
    }
  }

  static final Map<String, RegExp> _topicPatterns = {
    '工作': RegExp(r'工作|上班|加班|开会|项目|deadline', caseSensitive: false),
    '学业': RegExp(r'学习|考试|复习|作业|论文'),
    '吃饭': RegExp(r'吃饭|外卖|做饭|好吃|饿|早餐|午饭|晚饭'),
    '睡觉': RegExp(r'睡觉|睡了|好困|熬夜|失眠|起床'),
    '情绪': RegExp(r'难过|累了|好累|压力|烦|焦虑|emo', caseSensitive: false),
    '娱乐': RegExp(r'游戏|电影|追剧|音乐|唱歌|动漫'),
    '天气': RegExp(r'天气|下雨|下雪|好冷|好热|降温'),
    '周末': RegExp(r'周末|放假|假期|出去玩|旅行'),
  };
}
