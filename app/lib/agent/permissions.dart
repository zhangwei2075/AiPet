import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机能力域 —— M5「全权限」的授权单位。
///
/// 一个能力对应一组工具。默认 `allCapabilities` 全开，即智能体对本机拥有完整操作面；
/// 用户可以在「智能体 → 权限」里单独关掉某一项，或一键急停（[AgentPermissions.paused]）。
/// 能力是**授予**而不是沙箱白名单：关掉才限制，没关就能用。
enum AgentCapability {
  command('run_command', '终端命令', '执行 PowerShell / cmd / bash 命令'),
  process('process', '进程', '列出进程、结束进程'),
  launch('launch', '启动程序', '启动 exe、打开文件与网址'),
  fileRead('file', '读取文件', '读文件、列目录、搜内容'),
  fileWrite('file', '写入文件', '新建或覆盖文件'),
  fileDelete('file', '删除文件', '删除单个文件（不接受目录）'),
  clipboardWrite('clipboard_write', '写剪贴板', '把文本放进系统剪贴板'),
  network('http_request', '网络请求', '发起任意 HTTP 请求'),
  window('window', '窗口控制', '列出/置前/最小化/关闭窗口'),
  input('input', '键鼠模拟', '打字、按键、点击、移动光标'),
  screen('screenshot', '屏幕截图', '截取当前屏幕并保存 PNG'),
  mcp('mcp', '远程 MCP', '调用已连接的 MCP 服务器工具');

  const AgentCapability(this.toolName, this.label, this.detail);

  /// 该能力的主工具名（用于 UI 与模型提示）。file 三个能力共用 `file` 工具。
  final String toolName;
  final String label;
  final String detail;

  static const Set<AgentCapability> allCapabilities = {
    AgentCapability.command,
    AgentCapability.process,
    AgentCapability.launch,
    AgentCapability.fileRead,
    AgentCapability.fileWrite,
    AgentCapability.fileDelete,
    AgentCapability.clipboardWrite,
    AgentCapability.network,
    AgentCapability.window,
    AgentCapability.input,
    AgentCapability.screen,
    AgentCapability.mcp,
  };

  static AgentCapability? byName(String name) {
    for (final cap in values) {
      if (cap.name == name) return cap;
    }
    return null;
  }
}

/// 权限与自治策略。
///
/// 设计取向（见 `docs/autonomy.md`）：能力默认全开、动作全程留痕、随时可一键回收。
/// 唯一的默认拦截是 [defaultBlockedPatterns] 里几条**不可逆的系统级命令**；
/// 把 [blockIrreversible] 关掉即解除，达成字面意义上的「全部权限」。
@immutable
class AgentPermissions {
  const AgentPermissions({
    this.enabled = AgentCapability.allCapabilities,
    this.paused = false,
    this.auditEnabled = true,
    this.blockIrreversible = true,
    this.blockedPatterns = defaultBlockedPatterns,
    this.maxStepsPerGoal = 12,
    this.commandTimeoutSeconds = 120,
    this.maxOutputChars = 8000,
    this.selfDriveIntervalMinutes = 30,
  });

  /// 已授予的能力集合。默认全集 = 全权限。
  final Set<AgentCapability> enabled;

  /// 一键急停：true 时所有工具、自主循环、感知全部停摆（但设置与界面仍可操作）。
  final bool paused;

  /// 审计日志总开关（默认开；关掉后不再写入，历史不清）。
  final bool auditEnabled;

  /// 是否拦截不可逆的系统级命令。关掉后黑名单失效。
  final bool blockIrreversible;

  /// 命令黑名单（正则）。空列表 = 不拦任何命令。
  final List<String> blockedPatterns;

  /// 单个目标最多执行多少步，防止自主循环失控。
  final int maxStepsPerGoal;

  /// 单条命令的超时秒数，超时会 kill 进程。
  final int commandTimeoutSeconds;

  /// 工具输出回灌给模型的最大字符数（也用于审计摘要）。
  final int maxOutputChars;

  /// 空闲多久后自己发起一次只读巡检（分钟）。0 = 不自驱。
  final int selfDriveIntervalMinutes;

  bool get isFullAccess => enabled.length == AgentCapability.allCapabilities.length;

  bool allows(AgentCapability cap) => !paused && enabled.contains(cap);

  AgentPermissions withCapability(AgentCapability cap, bool value) {
    final next = Set<AgentCapability>.of(enabled);
    if (value) {
      next.add(cap);
    } else {
      next.remove(cap);
    }
    return copyWith(enabled: Set.unmodifiable(next));
  }

  AgentPermissions withAll(bool value) => copyWith(
        enabled: value
            ? AgentCapability.allCapabilities
            : const <AgentCapability>{},
      );

  /// 返回命中的黑名单条目；null 表示放行。
  /// 这是纯函数，测试可以直接喂命令字符串。
  String? blockedReason(String command) {
    if (!blockIrreversible) return null;
    for (final pattern in blockedPatterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      if (regex.hasMatch(command)) return pattern;
    }
    return null;
  }

  AgentPermissions copyWith({
    Set<AgentCapability>? enabled,
    bool? paused,
    bool? auditEnabled,
    bool? blockIrreversible,
    List<String>? blockedPatterns,
    int? maxStepsPerGoal,
    int? commandTimeoutSeconds,
    int? maxOutputChars,
    int? selfDriveIntervalMinutes,
  }) {
    return AgentPermissions(
      enabled: enabled ?? this.enabled,
      paused: paused ?? this.paused,
      auditEnabled: auditEnabled ?? this.auditEnabled,
      blockIrreversible: blockIrreversible ?? this.blockIrreversible,
      blockedPatterns: blockedPatterns ?? this.blockedPatterns,
      maxStepsPerGoal: maxStepsPerGoal ?? this.maxStepsPerGoal,
      commandTimeoutSeconds: commandTimeoutSeconds ?? this.commandTimeoutSeconds,
      maxOutputChars: maxOutputChars ?? this.maxOutputChars,
      selfDriveIntervalMinutes: selfDriveIntervalMinutes ?? this.selfDriveIntervalMinutes,
    );
  }

  /// 只拦「一次动作就抹掉整台机器」的命令；普通 rm / del / Remove-Item 一律放行。
  static const List<String> defaultBlockedPatterns = [
    r'\bformat\s+[a-z]:',
    r'\brm\s+-rf\s+[/\\](\s|$)',
    r'\brd\s+/s\s+/q\s+[a-z]:\\?\s*$',
    r'\bdel\s+/[fqs]+\s+[a-z]:\\windows',
    r'\bcipher\s+/w:[a-z]:',
    r'\bRemove-Item\b[^\n]*\b-Recurse\b[^\n]*\b(?:C:\\|/)\s*$',
  ];

  static const defaults = AgentPermissions();

  Map<String, dynamic> toJson() => {
        'enabled': [for (final cap in enabled) cap.name],
        'paused': paused,
        'auditEnabled': auditEnabled,
        'blockIrreversible': blockIrreversible,
        'blockedPatterns': blockedPatterns,
        'maxStepsPerGoal': maxStepsPerGoal,
        'commandTimeoutSeconds': commandTimeoutSeconds,
        'maxOutputChars': maxOutputChars,
        'selfDriveIntervalMinutes': selfDriveIntervalMinutes,
      };

  factory AgentPermissions.fromJson(Map<String, dynamic> json) {
    final caps = <AgentCapability>{};
    final rawCaps = json['enabled'];
    if (rawCaps is List) {
      for (final item in rawCaps) {
        final cap = AgentCapability.byName(item?.toString() ?? '');
        if (cap != null) caps.add(cap);
      }
    }
    final rawPatterns = json['blockedPatterns'];
    return AgentPermissions(
      // 旧配置缺字段时回落到「全开」，不因为一次升级悄悄收回权限。
      enabled: rawCaps is List ? Set.unmodifiable(caps) : AgentCapability.allCapabilities,
      paused: json['paused'] == true,
      auditEnabled: json['auditEnabled'] != false,
      blockIrreversible: json['blockIrreversible'] != false,
      blockedPatterns: rawPatterns is List
          ? [for (final p in rawPatterns) p.toString()]
          : defaultBlockedPatterns,
      maxStepsPerGoal: (json['maxStepsPerGoal'] as num?)?.toInt() ?? 12,
      commandTimeoutSeconds: (json['commandTimeoutSeconds'] as num?)?.toInt() ?? 120,
      maxOutputChars: (json['maxOutputChars'] as num?)?.toInt() ?? 8000,
      selfDriveIntervalMinutes: (json['selfDriveIntervalMinutes'] as num?)?.toInt() ?? 30,
    );
  }
}

/// 权限配置落盘。与 `TaskStore` / `McpStore` 一样用 shared_preferences。
class PermissionStore {
  PermissionStore({SharedPreferences? prefs, String key = prefsKey})
      : _prefs = prefs,
        _key = key;

  static const String prefsKey = 'agent.permissions.v1';

  SharedPreferences? _prefs;
  final String _key;

  Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<AgentPermissions> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AgentPermissions.defaults;
    try {
      return AgentPermissions.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AgentPermissions.defaults;
    }
  }

  Future<void> save(AgentPermissions permissions) async {
    final prefs = await _instance();
    await prefs.setString(_key, jsonEncode(permissions.toJson()));
  }
}
