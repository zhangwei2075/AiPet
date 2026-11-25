import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个 MCP 服务器的声明。连接仍是显式动作（启动时不会自动外连），默认关闭；
/// 连接成功后工具统一经 `ToolRuntime.wrap` 注册，受 `AgentCapability.mcp` 与审计约束（M5）。
@immutable
class McpServer {
  const McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = false,
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;

  McpServer copyWith({String? name, String? url, bool? enabled}) => McpServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
      };

  factory McpServer.fromJson(Map<String, dynamic> json) => McpServer(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名',
        url: json['url']?.toString() ?? '',
        enabled: json['enabled'] == true,
      );

  /// URL 安全校验：只允许 https，或本机 http（回环地址）。
  /// 防止配置被诱导填成内网/明文远端，把 Key 或剪贴板内容送出去。
  static String? validateUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '地址无效';
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && _isLoopback(uri.host)) return null;
    return '只用 https 或本机地址';
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

/// MCP 服务器配置的落盘。提示词/代码不落盘，只存声明。
class McpStore {
  McpStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const String prefsKey = 'agent.mcp.v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return _prefs = prefs;
  }

  Future<List<McpServer>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => McpServer.fromJson((item as Map).cast<String, dynamic>()))
          .where((s) => s.id.isNotEmpty && s.url.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<McpServer> servers) async {
    final prefs = await _instance();
    await prefs.setString(prefsKey, jsonEncode([for (final s in servers) s.toJson()]));
  }
}
