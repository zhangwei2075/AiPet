import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../app_version.dart';
import '../permissions.dart';
import '../pet_tool.dart';
import 'mcp_server.dart';

/// MCP 客户端：JSON-RPC 2.0 over HTTP（Streamable HTTP 的 JSON 响应分支）。
/// 不引入 MCP SDK —— 只用到 initialize / tools/list / tools/call 三个方法，
/// 手写比拉一整套协议栈更适合桌面宠物的轻量定位。
class McpClient {
  McpClient({http.Client? client, this.timeout = const Duration(seconds: 12)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  int _nextId = 1;
  String? _sessionId;

  /// 握手并列出工具。任何一步失败都抛 McpException，由 UI 显示。
  Future<List<McpTool>> connect(McpServer server) async {
    final problem = McpServer.validateUrl(server.url);
    if (problem != null) throw McpException(problem);
    _sessionId = null;

    await _rpc(server.url, 'initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': const {},
      'clientInfo': {'name': 'MomoPet', 'version': kAppVersion},
    });
    // 服务端可能通过 header 下发会话 id，后续请求要带上。
    final listed = await _rpc(server.url, 'tools/list', {}, session: _sessionId);
    final tools = listed['tools'] as List? ?? const [];
    return tools
        .whereType<Map>()
        .map((t) => McpTool(
              serverId: server.id,
              name: t['name']?.toString() ?? '',
              description: t['description']?.toString() ?? '',
              inputSchema: (t['inputSchema'] as Map?)?.cast<String, dynamic>() ?? const {},
              client: this,
              server: server,
            ))
        .where((t) => t.name.isNotEmpty)
        .toList(growable: false);
  }

  /// 调用远程工具，结果转成 PetTool 统一的 ToolResult。
  Future<ToolResult> call(McpServer server, String tool, Map<String, dynamic> args) async {
    final problem = McpServer.validateUrl(server.url);
    if (problem != null) return ToolResult.fail(problem);
    try {
      final data = await _rpc(server.url, 'tools/call', {
        'name': tool,
        'arguments': args,
      }, session: _sessionId);
      if (data['isError'] == true) return ToolResult.fail(_textOf(data));
      return ToolResult.ok(_textOf(data));
    } on McpException catch (error) {
      return ToolResult.fail(error.message);
    }
  }

  String _textOf(Map<String, dynamic> data) {
    final content = data['content'] as List? ?? const [];
    return content
        .whereType<Map>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text']?.toString() ?? '')
        .join('\n')
        .trim();
  }

  Future<Map<String, dynamic>> _rpc(
    String baseUrl,
    String method,
    Map<String, dynamic> params, {
    String? session,
  }) async {
    final uri = Uri.parse(baseUrl);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    };
    if (session != null) headers['Mcp-Session-Id'] = session;

    final response = await _client
        .post(
          uri,
          headers: headers,
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': _nextId++,
            'method': method,
            'params': params,
          }),
        )
        .timeout(timeout);

    final sessionHeader = response.headers['mcp-session-id'];
    if (sessionHeader != null) _sessionId = sessionHeader;

    if (response.statusCode >= 400) {
      throw McpException('MCP 返回 ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    // Streamable HTTP 可能回 SSE 帧（data: {...}），取第一条 data 即可。
    final payload = body.startsWith('data:')
        ? body.split('\n').firstWhere((l) => l.startsWith('data:')).substring(5).trim()
        : body;
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      throw McpException('MCP 返回格式无法解析');
    }
    if (decoded is! Map<String, dynamic>) throw McpException('MCP 返回不是对象');
    final error = decoded['error'];
    if (error != null) throw McpException(error['message']?.toString() ?? 'MCP 调用失败');
    return (decoded['result'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  void close() => _client.close();
}

/// 远程 MCP 工具包装成 PetTool，让 Brain 的注册表统一调度。
class McpTool extends PetTool {
  McpTool({
    required this.serverId,
    required this.name,
    required this.description,
    this.inputSchema = const {},
    this.client,
    this.server,
  });

  final String serverId;
  final McpClient? client;
  final McpServer? server;
  @override
  final String name;
  @override
  final String description;
  @override
  Map<String, dynamic> get parametersSchema => inputSchema;
  final Map<String, dynamic> inputSchema;

  /// 远程调用默认是慢工具：先回「我去看看」，后台执行。
  @override
  bool get slow => true;

  /// 远程工具单独一个能力域，受 ToolRuntime 的权限校验与审计覆盖。
  @override
  AgentCapability get capability => AgentCapability.mcp;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final c = client;
    final s = server;
    if (c == null || s == null) return const ToolResult.fail('MCP 工具未绑定服务器');
    return c.call(s, name, args);
  }
}

class McpException implements Exception {
  const McpException(this.message);
  final String message;
  @override
  String toString() => message;
}
