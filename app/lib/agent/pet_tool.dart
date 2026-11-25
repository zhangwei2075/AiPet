import 'package:flutter/foundation.dart';

import 'permissions.dart';

/// 工具执行结果：ok=false 时 message 是给用户看的失败说明。
@immutable
class ToolResult {
  const ToolResult.ok(this.message) : success = true;
  const ToolResult.fail(this.message) : success = false;

  final bool success;
  final String message;
}

/// 模型（或规则表）解析出的「一次工具调用意图」。
@immutable
class ToolIntent {
  const ToolIntent(this.tool, this.args);

  final String tool;
  final Map<String, dynamic> args;
}

/// 内置工具接口 —— DSH「一切皆插件」的 Dart 版：
/// name/description/schema 三件套同时喂给 function calling 和文档。
/// M1 工具是进程内置的；M4 会把注册表挪进 brainpack.json 配置化。
abstract class PetTool {
  const PetTool();

  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema;

  /// 慢工具（网络查询等）标记：true 时 Brain 先回一句「我去看看」，
  /// 执行完再汇报，不阻塞聊天流（M3 异步 ReAct）。
  bool get slow => false;

  /// 该工具需要的能力域。null = 内置工具，不额外校验（M5 之前就存在的能力）。
  AgentCapability? get capability => null;

  /// 执行前的策略校验。返回非 null 表示拒绝执行，字符串是给用户看的理由。
  /// 命令类工具用它做不可逆命令拦截；其余工具用默认实现即可。
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) => null;

  Future<ToolResult> invoke(Map<String, dynamic> args);
}

/// 工具注册表：Brain 执行意图时按名字取用。
class ToolRegistry {
  final Map<String, PetTool> _tools = {};

  void register(PetTool tool) => _tools[tool.name] = tool;

  PetTool? lookup(String name) => _tools[name];

  List<PetTool> get all => _tools.values.toList(growable: false);

  /// OpenAI function calling 的 tools 参数。
  List<Map<String, dynamic>> toOpenAiTools() => [
        for (final tool in _tools.values)
          {
            'type': 'function',
            'function': {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.parametersSchema,
            },
          },
      ];
}
