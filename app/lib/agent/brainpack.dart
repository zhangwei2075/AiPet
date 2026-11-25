import 'dart:convert';

import 'package:flutter/foundation.dart';

/// brainpack.json —— 智能体能力清单，仿 petpack 的「元数据 + 声明」格式。
///
/// M5 之后这里的语义是**能力开关表**，不再是能力上限：清单里列的是所有可开关的
/// 内置工具（含本机全权限工具），缺省即启用。真正的授权边界在
/// `AgentPermissions`（`permissions.dart`）——它决定能力是否授予、是否急停、是否留痕。
///
/// 仍然是**配置**不是代码：第三方只能开关内置能力、调参数，不能注入任意 Dart
/// 代码或任意 HTTP 端点（不做 npm 插件兼容，见设计稿 §3）。未知条目跳过并记警告。
///
/// 格式示例：
/// ```json
/// {
///   "schemaVersion": 1,
///   "name": "有财的智能体",
///   "tools": {
///     "reminder": true,
///     "clipboard": true,
///     "run_command": true,
///     "file_write": true
///   },
///   "triggers": { "clipboard": true, "app_focus": true },
///   "watchdog": { "maxAttempts": 3, "stuckTimeoutSeconds": 120 },
///   "quietHours": { "start": 0, "end": 0, "dailyBudget": 240 }
/// }
/// ```
@immutable
class BrainPack {
  const BrainPack({
    this.name = '默认智能体',
    this.schemaVersion = 1,
    this.tools = const {},
    this.triggers = const {},
    this.watchdog = const {},
    this.quietHours = const {},
    this.warnings = const [],
  });

  final String name;
  final int schemaVersion;

  /// 工具开关：键必须命中内置白名单，否则进 warnings 并忽略。
  final Map<String, bool> tools;

  /// Trigger 开关。M5 起感知默认启用（全权限方向），显式 false 才关掉。
  final Map<String, bool> triggers;

  final Map<String, dynamic> watchdog;
  final Map<String, dynamic> quietHours;

  /// 解析时收集的非致命问题（未知条目、类型错误）。
  final List<String> warnings;

  /// 白名单内缺省即启用；白名单外一律视为未启用（防同名劫持 / 未知条目）。
  bool toolEnabled(String name, {bool fallback = true}) =>
      builtInTools.contains(name) ? (tools[name] ?? fallback) : false;
  bool triggerEnabled(String name, {bool fallback = true}) =>
      builtInTriggers.contains(name) ? (triggers[name] ?? fallback) : false;

  BrainPack copyWithTool(String name, bool value) => BrainPack(
        name: this.name,
        schemaVersion: schemaVersion,
        tools: {...tools, name: value},
        triggers: triggers,
        watchdog: watchdog,
        quietHours: quietHours,
        warnings: warnings,
      );

  BrainPack copyWithTrigger(String name, bool value) => BrainPack(
        name: this.name,
        schemaVersion: schemaVersion,
        tools: tools,
        triggers: {...triggers, name: value},
        watchdog: watchdog,
        quietHours: quietHours,
        warnings: warnings,
      );

  int watchdogInt(String key, int fallback) => (watchdog[key] as num?)?.toInt() ?? fallback;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'name': name,
        'tools': tools,
        'triggers': triggers,
        if (watchdog.isNotEmpty) 'watchdog': watchdog,
        if (quietHours.isNotEmpty) 'quietHours': quietHours,
      };

  factory BrainPack.fromJson(Map<String, dynamic> json) {
    final warnings = <String>[];
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > 1) warnings.add('schemaVersion=$version 高于支持的 1，按 v1 解析');

    Map<String, bool> parseSwitches(String key, Set<String> whitelist) {
      final raw = json[key];
      if (raw is! Map) return const {};
      final out = <String, bool>{};
      raw.forEach((k, v) {
        final name = k.toString();
        if (!whitelist.contains(name)) {
          warnings.add('未知 $key 条目：$name（已忽略）');
          return;
        }
        if (v is bool) {
          out[name] = v;
        } else {
          warnings.add('$key.$name 不是布尔值（已忽略）');
        }
      });
      return out;
    }

    final tools = parseSwitches('tools', builtInTools);
    final triggers = parseSwitches('triggers', builtInTriggers);
    final watchdog = (json['watchdog'] as Map?)?.cast<String, dynamic>() ?? const {};
    final quiet = (json['quietHours'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BrainPack(
      name: json['name']?.toString() ?? '默认智能体',
      schemaVersion: version,
      tools: tools,
      triggers: triggers,
      watchdog: watchdog,
      quietHours: quiet,
      warnings: List.unmodifiable(warnings),
    );
  }

  factory BrainPack.fromText(String raw) {
    try {
      return BrainPack.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('[brainpack] 解析失败，用默认配置: $error');
      return const BrainPack(warnings: ['配置文件损坏，已回退默认']);
    }
  }

  /// M1 内置 + M5 本机全权限工具。缺省即启用；关掉只是从模型工具清单里摘掉，
  /// 权限层的否决见 `ToolRuntime.execute`。
  static const Set<String> builtInTools = {
    // M1 陪伴工具
    'reminder',
    'clipboard',
    'pet_control',
    // M5 本机执行
    'run_command',
    'process',
    'launch',
    'http_request',
    // M5 文件与剪贴板
    'file_read',
    'file_write',
    'file_list',
    'file_search',
    'file_delete',
    'clipboard_write',
    // M5 桌面交互
    'window',
    'input',
    'screenshot',
    // 资讯订阅（简讯）
    'watch_create',
    'watch_list',
    'watch_run',
    'watch_delete',
  };

  static const Set<String> builtInTriggers = {
    'clipboard',
    'app_focus',
  };

  /// 默认配置：工具与感知 Trigger 全开（M5 全权限默认）。
  static const defaults = BrainPack();
}
