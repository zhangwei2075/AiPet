import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 技能开关的落盘：只存 id→bool，提示词本身在代码里（不可注入）。
class SkillStore {
  SkillStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const String prefsKey = 'agent.skills.v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async => _prefs ??= await SharedPreferences.getInstance();

  Future<Map<String, bool>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v == true));
    } catch (_) {
      return const {};
    }
  }

  Future<void> save(Map<String, bool> switches) async {
    await (await _instance()).setString(prefsKey, jsonEncode(switches));
  }
}
