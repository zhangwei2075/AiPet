import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat.dart';
import '../models/settings.dart';
import 'activity.dart';
import 'audit_log.dart';
import 'experience.dart';
import 'pet_tool.dart';
import 'tool_runtime.dart';

/// 聊天里实际执行过的一步。
class ChatAgentStep {
  const ChatAgentStep({
    required this.tool,
    required this.argsSummary,
    required this.ok,
    required this.output,
  });

  final String tool;
  final String argsSummary;
  final bool ok;
  final String output;
}

class ChatAgentResult {
  const ChatAgentResult({
    required this.text,
    required this.steps,
    required this.rounds,
  });

  final String text;
  final List<ChatAgentStep> steps;
  final int rounds;

  bool get usedTools => steps.isNotEmpty;
  bool get allOk => steps.every((s) => s.ok);
}

class ChatAgentException implements Exception {
  const ChatAgentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 聊天主通道的 ReAct 执行器。
///
/// 之前「通过对话不能操作电脑」的真正原因不只是提示词：在线聊天是纯文本流式
/// 请求，既没带 tools，也没有执行回路，模型再怎么说「我可以」也只是嘴上说说。
/// 这里把聊天变成带 function calling 的多轮循环：
/// ```
/// 用户文本 → 模型(tools) → tool_calls → ToolRuntime 真实执行
///          → 结果以 tool 消息回灌 → 模型继续 → 直到给出最终文字
/// ```
/// 所有工具都走 ToolRuntime，与自主循环共用同一套权限校验 / 审计 / 状态上报。
class ChatAgent {
  ChatAgent({
    required ToolRegistry registry,
    required ToolRuntime runtime,
    http.Client? client,
    AgentActivity? activity,
    ExperienceBank? experience,
    this.maxToolRounds = 6,
  })  : _registry = registry,
        _runtime = runtime,
        _client = client ?? http.Client(),
        _activity = activity,
        _experience = experience;

  final ToolRegistry _registry;
  final ToolRuntime _runtime;
  final http.Client _client;
  final AgentActivity? _activity;
  final ExperienceBank? _experience;
  final int maxToolRounds;

  static const Duration requestTimeout = Duration(seconds: 40);

  Future<ChatAgentResult> respond({
    required String input,
    required List<ChatMessage> history,
    required AppSettings settings,
    required String systemPrompt,
  }) async {
    final anthropic = settings.apiProtocol == 'anthropic';
    final recent = history.length <= 8 ? history : history.sublist(history.length - 8);
    final messages = <Map<String, dynamic>>[
      ...recent.map((m) => <String, dynamic>{
            'role': m.role == ChatRole.user ? 'user' : 'assistant',
            'content': m.text,
          }),
      <String, dynamic>{'role': 'user', 'content': input},
    ];
    final steps = <ChatAgentStep>[];
    var rounds = 0;

    for (var round = 0; round < maxToolRounds; round++) {
      rounds = round + 1;
      final raw = await _request(
        anthropic: anthropic,
        settings: settings,
        systemPrompt: systemPrompt,
        messages: messages,
      );
      final calls = anthropic
          ? _parseAnthropicCalls(raw)
          : _parseOpenAiCalls(raw);
      final text = anthropic ? _anthropicText(raw) : _openAiText(raw);

      if (calls.isEmpty) {
        final answer = text.trim();
        if (answer.isEmpty) throw const ChatAgentException('模型返回了空消息');
        await _afterRun(goal: input, steps: steps, answer: answer);
        return ChatAgentResult(text: answer, steps: steps, rounds: rounds);
      }

      // 把 assistant 的 tool_calls 原样留在上下文里，结果才能合法回灌。
      if (anthropic) {
        messages.add(<String, dynamic>{'role': 'assistant', 'content': raw['content']});
        final results = <Map<String, dynamic>>[];
        for (final call in calls) {
          final step = await _runTool(call.name, call.args);
          steps.add(step);
          results.add(<String, dynamic>{
            'type': 'tool_result',
            'tool_use_id': call.id,
            'content': step.output,
          });
        }
        messages.add(<String, dynamic>{'role': 'user', 'content': results});
      } else {
        messages.add(<String, dynamic>{
          'role': 'assistant',
          'content': text,
          'tool_calls': [
            for (final call in calls)
              <String, dynamic>{
                'id': call.id,
                'type': 'function',
                'function': <String, dynamic>{
                  'name': call.name,
                  'arguments': jsonEncode(call.args),
                },
              },
          ],
        });
        for (final call in calls) {
          final step = await _runTool(call.name, call.args);
          steps.add(step);
          messages.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': call.id,
            'content': step.output,
          });
        }
      }
    }

    // 轮次用尽：把已经做过的真实结果交代清楚，绝不假装全部完成。
    final answer = '这件事我连续做了 ${steps.length} 步还没收尾，先停一下。'
        '已执行：${steps.map((s) => s.tool).join('、')}。'
        '${steps.isEmpty ? '' : '最后一步结果：${_clip(steps.last.output, 160)}'}'
        ' 想让我继续就说「继续」。';
    await _afterRun(goal: input, steps: steps, answer: answer);
    return ChatAgentResult(text: answer, steps: steps, rounds: rounds);
  }

  Future<ChatAgentStep> _runTool(String name, Map<String, dynamic> args) async {
    final tool = _registry.lookup(name);
    final ToolResult result;
    if (tool == null) {
      result = ToolResult.fail('工具 $name 没有注册，请改用清单里的工具。');
    } else {
      result = await _runtime.executeTracked(tool, args, source: 'user');
    }
    final limit = _runtime.permissions.maxOutputChars;
    return ChatAgentStep(
      tool: name,
      argsSummary: summarizeArgs(args, limit: 160),
      ok: result.success,
      output: _clip(result.message, limit),
    );
  }

  Future<void> _afterRun({
    required String goal,
    required List<ChatAgentStep> steps,
    required String answer,
  }) async {
    if (steps.isEmpty) return;
    final ok = steps.every((s) => s.ok);
    _activity?.endGoal(ok: ok, summary: _clip(answer.replaceAll(RegExp(r'\s+'), ' '), 160));
    try {
      await _experience?.record(
        goal: goal,
        ok: ok,
        tools: [for (final s in steps) s.tool],
        summary: answer,
        origin: 'chat',
      );
    } catch (_) {
      // 经验写盘失败不影响本轮回复。
    }
  }

  // ------------------------------------------------------------- 协议请求

  Future<Map<String, dynamic>> _request({
    required bool anthropic,
    required AppSettings settings,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const ChatAgentException('还没有填写 API 地址');
    final uri = Uri.parse(anthropic ? '$base/messages' : '$base/chat/completions');
    final body = anthropic
        ? <String, dynamic>{
            'model': settings.model,
            'max_tokens': 800,
            'system': systemPrompt,
            'messages': messages,
            'tools': [
              for (final tool in _registry.all)
                <String, dynamic>{
                  'name': tool.name,
                  'description': tool.description,
                  'input_schema': tool.parametersSchema,
                },
            ],
            'stream': false,
          }
        : <String, dynamic>{
            'model': settings.model,
            'messages': [
              <String, dynamic>{'role': 'system', 'content': systemPrompt},
              ...messages,
            ],
            'tools': [
              for (final tool in _registry.all)
                <String, dynamic>{
                  'type': 'function',
                  'function': <String, dynamic>{
                    'name': tool.name,
                    'description': tool.description,
                    'parameters': tool.parametersSchema,
                  },
                },
            ],
            'tool_choice': 'auto',
            'temperature': 0.2,
            'max_tokens': 800,
            'stream': false,
          };
    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: _headers(settings, anthropic: anthropic), body: jsonEncode(body))
          .timeout(requestTimeout);
    } catch (error) {
      throw ChatAgentException('连接模型失败：$error');
    }
    if (response.statusCode >= 400) {
      final detail = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw ChatAgentException(
        '模型返回 ${response.statusCode}（可能不支持 tools）：${_clip(detail, 160)}',
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const ChatAgentException('模型返回不是合法 JSON');
    }
  }

  Map<String, String> _headers(AppSettings settings, {required bool anthropic}) => {
        'Content-Type': 'application/json',
        if (anthropic) 'anthropic-version': '2023-06-01',
        if (settings.apiKey.trim().isNotEmpty) ...{
          if (anthropic) 'x-api-key': settings.apiKey.trim(),
          if (!anthropic || settings.isOpencodeGateway)
            'Authorization': 'Bearer ${settings.apiKey.trim()}',
        },
        if (settings.isOpencodeGateway) 'x-opencode-session': settings.opencodeSessionId,
      };

  // ------------------------------------------------------------- 响应解析

  String _openAiText(Map<String, dynamic> data) =>
      (((data['choices'] as List?)?.firstOrNull as Map?)?['message']?['content'])
          ?.toString() ??
      '';

  List<_ToolCall> _parseOpenAiCalls(Map<String, dynamic> data) {
    final message = ((data['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?;
    final calls = message?['tool_calls'] as List?;
    if (calls == null) return const [];
    return [
      for (final item in calls)
        if (item is Map) ..._oneOpenAiCall(item.cast<String, dynamic>()),
    ];
  }

  Iterable<_ToolCall> _oneOpenAiCall(Map<String, dynamic> call) sync* {
    final function = call['function'] as Map?;
    final name = function?['name']?.toString();
    if (name == null || name.isEmpty) return;
    Map<String, dynamic> args = const {};
    final raw = function?['arguments']?.toString();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) args = decoded.cast<String, dynamic>();
      } catch (_) {
        // 参数坏了就给空参数，让工具自己报「缺少参数」，不静默跳过。
      }
    }
    yield _ToolCall(
      id: call['id']?.toString() ?? 'call-${name.hashCode}',
      name: name,
      args: args,
    );
  }

  String _anthropicText(Map<String, dynamic> data) => (data['content'] as List? ?? const [])
      .whereType<Map>()
      .where((block) => block['type'] == 'text')
      .map((block) => block['text']?.toString() ?? '')
      .join()
      .trim();

  List<_ToolCall> _parseAnthropicCalls(Map<String, dynamic> data) => [
        for (final block in (data['content'] as List? ?? const []))
          if (block is Map && block['type'] == 'tool_use')
            _ToolCall(
              id: block['id']?.toString() ?? '',
              name: block['name']?.toString() ?? '',
              args: (block['input'] as Map?)?.cast<String, dynamic>() ?? const {},
            ),
      ];

  static String _clip(String text, int limit) {
    final clean = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return clean.length <= limit ? clean : '${clean.substring(0, limit)}…（输出已截断）';
  }
}

class _ToolCall {
  const _ToolCall({required this.id, required this.name, required this.args});

  final String id;
  final String name;
  final Map<String, dynamic> args;
}
