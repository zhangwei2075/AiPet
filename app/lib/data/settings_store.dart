import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';
import '../models/settings.dart';

class SettingsStore {
  static const _settingsKey = 'aipet.settings.v1';
  static const _historyKey = 'aipet.history.v1';

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<Map<String, List<ChatMessage>>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map((petId, value) {
        final list = (value as List)
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList();
        return MapEntry(petId, list);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> saveHistory(Map<String, List<ChatMessage>> history) async {
    final prefs = await SharedPreferences.getInstance();
    final data = history.map(
      (petId, messages) => MapEntry(petId, messages.map((m) => m.toJson()).toList()),
    );
    await prefs.setString(_historyKey, jsonEncode(data));
  }
}
