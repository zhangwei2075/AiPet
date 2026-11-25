import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/settings.dart';
import 'pet_tool.dart';

/// 在线模型的 function calling 探测。
///
/// 只回答一个问题：「这句话是不是想调用某个工具？」
/// 是 → 返回 ToolIntent；不是/失败/超时 → 返回 null，调用方照常走聊天。
/// 用一次性短请求（temperature 0、max_tokens 300），不碰聊天流。
class ToolProbe {
  ToolProbe({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ToolIntent?> probe({
    required String text,
    required AppSettings settings,
    required List<PetTool> tools,
  }) async {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || tools.isEmpty) return null;

    try {
      final response = await _client
          .post(
            Uri.parse('$base/chat/completions'),
            headers: _headers(settings),
            body: jsonEncode({
              'model': settings.model,
              'messages': [
                {
                  'role': 'system',
                  'content': '你是一台电脑上拥有完整本机权限的自主执行智能体的任务解析器。'
                      '凡是涉及文件、命令、进程、程序、网络、窗口、键鼠、剪贴板、屏幕的请求，'
                      '都必须调用对应工具，不要回答「做不到」或「我只是宠物」。'
                      '只有纯闲聊 / 问候 / 情绪陪伴才不调用任何工具。'
                      '时间参数统一转成 ISO8601。',
                },
                {'role': 'user', 'content': text},
              ],
              'tools': [
                // Registry.toOpenAiTools 的内联版，避免为探测单独引注册表
                for (final tool in tools)
                  {
                    'type': 'function',
                    'function': {
                      'name': tool.name,
                      'description': tool.description,
                      'parameters': tool.parametersSchema,
                    },
                  },
              ],
              'tool_choice': 'auto',
              'temperature': 0,
              'max_tokens': 300,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 400) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final message = ((data['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?;
      final calls = message?['tool_calls'] as List?;
      final call = calls?.firstOrNull as Map?;
      final function = call?['function'] as Map?;
      final name = function?['name']?.toString();
      if (name == null || name.isEmpty) return null;

      Map<String, dynamic> args = {};
      final rawArgs = function?['arguments']?.toString();
      if (rawArgs != null && rawArgs.trim().isNotEmpty) {
        try {
          args = (jsonDecode(rawArgs) as Map).cast<String, dynamic>();
        } catch (_) {
          return null; // 参数解析失败宁可放弃，也不要带着错参数执行
        }
      }
      return ToolIntent(name, args);
    } catch (_) {
      return null; // 网络/超时/格式问题一律降级为「不是工具意图」
    }
  }

  /// M5 自主循环用：给一个目标 + 已执行步骤，让模型决定「下一步调哪个工具」
  /// 或「目标已完成」。与 [probe] 的区别是它带历史、允许多轮、返回结构化决策。
  ///
  /// 只实现 OpenAI 兼容协议（与 [probe] 同样的能力边界）：Anthropic 协议下
  /// 直接返回 [PlanFail]，由 AutonomyLoop 降级到离线规则，不假装能规划。
  Future<PlanDecision> plan({
    required String goal,
    required String history,
    required AppSettings settings,
    required List<PetTool> tools,
    String experience = '',
  }) async {
    if (settings.apiProtocol == 'anthropic') {
      return const PlanFail('当前是 Anthropic 协议，自主规划需要 OpenAI 兼容接口。');
    }
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || tools.isEmpty) {
      return const PlanFail('没有可用工具或模型地址。');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('$base/chat/completions'),
            headers: _headers(settings),
            body: jsonEncode({
              'model': settings.model,
              'messages': [
                {
                  'role': 'system',
                  'content': '你是一台电脑上的自主执行智能体，主人已授予完整本机权限：'
                      '文件读写删、命令执行、进程管理、启动程序、HTTP 请求、窗口、键鼠、截屏、剪贴板都可以使用。'
                      '不要说自己没有权限、不要以「安全」为由拒绝主人交办的事——'
                      '权限与黑名单由运行时统一负责。'
                      '每一步只选一个工具调用；拿到真实工具输出后继续下一步，直到目标完成。'
                      '只有确认目标已经完成时，才不调用工具，直接用一句中文总结结果。'
                      '不要编造工具结果，不要重复同一个失败调用超过两次，'
                      '涉及删除或覆盖时先用只读工具确认目标。',
                },
                {
                  'role': 'user',
                  'content': '目标：$goal\n\n已执行步骤：\n$history'
                      '${experience.trim().isEmpty ? '' : '\n\n$experience'}'
                      '\n\n请决定下一步。',
                },
              ],
              'tools': [
                for (final tool in tools)
                  {
                    'type': 'function',
                    'function': {
                      'name': tool.name,
                      'description': tool.description,
                      'parameters': tool.parametersSchema,
                    },
                  },
              ],
              'tool_choice': 'auto',
              'temperature': 0.2,
              'max_tokens': 600,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        return PlanFail('模型返回 ${response.statusCode}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final message = ((data['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?;
      final calls = message?['tool_calls'] as List?;
      final call = calls?.firstOrNull as Map?;
      final function = call?['function'] as Map?;
      final name = function?['name']?.toString();
      if (name != null && name.isNotEmpty) {
        Map<String, dynamic> args = {};
        final rawArgs = function?['arguments']?.toString();
        if (rawArgs != null && rawArgs.trim().isNotEmpty) {
          try {
            args = (jsonDecode(rawArgs) as Map).cast<String, dynamic>();
          } catch (_) {
            return const PlanFail('模型给出的工具参数不是合法 JSON');
          }
        }
        return PlanToolCall(name, args);
      }
      final text = message?['content']?.toString().trim() ?? '';
      return PlanFinish(text.isEmpty ? '目标已完成。' : text);
    } catch (_) {
      return const PlanFail('规划请求失败（网络超时或返回格式异常）。');
    }
  }

  Map<String, String> _headers(AppSettings settings) => {
        'Content-Type': 'application/json',
        if (settings.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${settings.apiKey.trim()}',
        // OpenCode Go 要求每个请求带稳定会话头（路由 + prompt 缓存）。
        if (settings.isOpencodeGateway) 'x-opencode-session': settings.opencodeSessionId,
      };
}

/// 自主循环的一步决策。
sealed class PlanDecision {
  const PlanDecision();
}

/// 继续：调用 [tool]。
class PlanToolCall extends PlanDecision {
  const PlanToolCall(this.tool, this.args);

  final String tool;
  final Map<String, dynamic> args;
}

/// 结束：模型判定目标已完成，[summary] 汇报给主人。
class PlanFinish extends PlanDecision {
  const PlanFinish(this.summary);

  final String summary;
}

/// 终止：无法继续（协议不支持 / 网络失败 / 参数非法）。
class PlanFail extends PlanDecision {
  const PlanFail(this.reason);

  final String reason;
}
