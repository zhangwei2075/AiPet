import 'package:flutter/foundation.dart';

/// 勿扰策略：程序级过滤的第一道闸门。
///
/// M5 起默认**不设静默、不限次数**：`startHour == endHour` 表示全天允许，
/// 每日预算 240 次、冷却 10 秒只用于防抖，不再压制自主行为。
/// 需要陪伴模式时在设置里改回 22:00–08:00 / 6 次 / 90 秒即可，
/// 规则本身仍是确定性的、零模型成本：
/// · 静默时段内不主动搭话，除非是到期提醒；
/// · 每自然日主动事件配额，用完不再触发；
/// · 同一 Trigger 的冷却时间，防抖。
@immutable
class QuietHours {
  const QuietHours({
    this.startHour = 0,
    this.endHour = 0,
    this.dailyBudget = 240,
    this.cooldown = const Duration(seconds: 10),
  })  : assert(startHour >= 0 && startHour < 24),
        assert(endHour >= 0 && endHour < 24);

  final int startHour;
  final int endHour;
  final int dailyBudget;
  final Duration cooldown;

  /// M5 默认 0/0（start==end）→ 不配置静默时段，全天允许主动行为。
  bool get isConfigured => startHour != endHour;

  bool isQuiet(DateTime now) {
    if (!isConfigured) return false;
    final h = now.hour;
    return startHour > endHour
        ? (h >= startHour || h < endHour)
        : (h >= startHour && h < endHour);
  }
}

/// 有状态的策略执行器：记录今日次数与每个 Trigger 的最近触发时间。
class QuietPolicy {
  QuietPolicy({QuietHours rules = const QuietHours(), DateTime Function()? now})
      : _rules = rules,
        _now = now ?? DateTime.now;

  final QuietHours _rules;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastFired = {};
  String _budgetDay = '';
  int _budgetUsed = 0;

  /// 返回是否允许这次主动事件；允许则记账。
  bool allow(String triggerName, {DateTime? at, bool ignoreQuiet = false}) {
    final now = at ?? _now();
    final day = '${now.year}-${now.month}-${now.day}';
    if (day != _budgetDay) {
      _budgetDay = day;
      _budgetUsed = 0;
    }
    if (!ignoreQuiet && _rules.isQuiet(now)) return false;
    if (_budgetUsed >= _rules.dailyBudget) return false;
    final last = _lastFired[triggerName];
    if (last != null && now.difference(last) < _rules.cooldown) return false;
    _budgetUsed++;
    _lastFired[triggerName] = now;
    return true;
  }

  /// 是否处于静默时段（转发规则，供投机执行等消费者查询而不记账）。
  bool isQuiet(DateTime now) => _rules.isQuiet(now);

  /// 剩余配额（设置页可展示）。
  int get remainingBudget => (_budgetUsed >= _rules.dailyBudget ? 0 : _rules.dailyBudget - _budgetUsed);

  void reset() {
    _lastFired.clear();
    _budgetDay = '';
    _budgetUsed = 0;
  }
}
