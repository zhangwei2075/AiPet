import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'persisted_task.dart';

/// 任务表的落盘实现：shared_preferences 里存一份 JSON 数组。
/// M1 只有一张表；M3 Watchdog 会在此之上加巡视与补偿。
class TaskStore {
  TaskStore({SharedPreferences? prefs, String key = 'agent.tasks.v1'})
      : _prefs = prefs,
        _key = key;

  static const String prefsKey = 'agent.tasks.v1';

  SharedPreferences? _prefs;
  final String _key;

  Future<SharedPreferences> _instance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<PersistedTask>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in list)
          PersistedTask.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      // 坏数据宁可清空重来，也不要让 Brain 起不来。
      return const [];
    }
  }

  Future<void> save(List<PersistedTask> tasks) async {
    final prefs = await _instance();
    await prefs.setString(
      _key,
      jsonEncode([for (final task in tasks) task.toJson()]),
    );
  }
}
