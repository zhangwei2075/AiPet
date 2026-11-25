import 'package:flutter/foundation.dart';

import 'activity.dart';
import 'audit_log.dart';
import 'permissions.dart';
import 'pet_tool.dart';

/// 所有工具执行的唯一入口（M5）。
///
/// 用装饰者把注册表里的每个 `PetTool` 包一层：能力校验 → 策略校验 → 执行 → 审计留痕。
/// 这样 M1 的老工具、MCP 远程工具、M5 新增的本机工具走的是同一套管治路径，
/// 不会出现「某个入口绕过权限」的漏洞（详见 `docs/autonomy.md` §4）。
class ToolRuntime {
  ToolRuntime({
    AgentPermissions permissions = AgentPermissions.defaults,
    AuditLog? audit,
    AgentActivity? activity,
    DateTime Function()? now,
  })  : _permissions = permissions,
        _audit = audit ?? AuditLog(),
        _activity = activity,
        _now = now ?? DateTime.now;

  AgentPermissions _permissions;
  final AuditLog _audit;
  final AgentActivity? _activity;
  final DateTime Function() _now;

  AgentPermissions get permissions => _permissions;
  AuditLog get audit => _audit;

  /// 设置页热改权限后立即生效，不需要重建 Brain 或重新注册工具。
  void applyPermissions(AgentPermissions next) => _permissions = next;

  /// 把工具包装成受管治版本，注册进 Brain 的 ToolRegistry。
  PetTool wrap(PetTool tool) => _GovernedTool(tool, this);

  /// 自主循环用：从注册表拿到的是包装工具，这里拆回内层并标注来源 `goal`，
  /// 避免二次包装，也让审计能区分「主人吩咐」和「它自己决定」。
  Future<ToolResult> executeTracked(
    PetTool tool,
    Map<String, dynamic> args, {
    required String source,
  }) {
    final inner = tool is _GovernedTool ? tool._inner : tool;
    return execute(inner, args, source: source);
  }

  /// 直接执行一次（不经注册表的场景，如自主循环拿到工具对象）。
  Future<ToolResult> execute(
    PetTool tool,
    Map<String, dynamic> args, {
    String source = 'user',
  }) async {
    _activity?.beginTool(tool.name, args, source: source);
    late final ToolResult result;
    if (_permissions.paused) {
      result = const ToolResult.fail('智能体已暂停，去「智能体 → 权限」恢复。');
    } else {
      final cap = tool.capability;
      if (cap != null && !_permissions.allows(cap)) {
        result = ToolResult.fail('能力「${cap.label}」未授予，先去「智能体 → 权限」打开。');
      } else {
        final problem = tool.validate(args, _permissions);
        if (problem != null) {
          await _writeAudit(tool, args, false, '已拦截：$problem', 0, source);
          result = ToolResult.fail('已拦截不可逆命令：$problem');
        } else {
          final sw = Stopwatch()..start();
          try {
            result = await tool.invoke(args);
          } catch (error) {
            result = ToolResult.fail('工具异常：$error');
          }
          sw.stop();
          await _writeAudit(tool, args, result.success, result.message, sw.elapsedMilliseconds, source);
        }
      }
    }
    _activity?.endTool(ok: result.success, output: truncate(result.message.replaceAll(RegExp(r'\s+'), ' ').trim(), 300));
    return result;
  }

  Future<void> _writeAudit(
    PetTool tool,
    Map<String, dynamic> args,
    bool ok,
    String output,
    int elapsedMs,
    String source,
  ) async {
    if (!_permissions.auditEnabled) return;
    try {
      await _audit.record(
        tool: tool.name,
        args: args,
        ok: ok,
        output: output,
        elapsedMs: elapsedMs,
        source: source,
        at: _now(),
      );
    } catch (error) {
      // 审计失败绝不能拖垮工具本身。
      debugPrint('[runtime] 审计写入失败: $error');
    }
  }
}

class _GovernedTool extends PetTool {
  const _GovernedTool(this._inner, this._runtime);

  final PetTool _inner;
  final ToolRuntime _runtime;

  @override
  String get name => _inner.name;

  @override
  String get description => _inner.description;

  @override
  Map<String, dynamic> get parametersSchema => _inner.parametersSchema;

  @override
  bool get slow => _inner.slow;

  @override
  AgentCapability? get capability => _inner.capability;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) =>
      _inner.validate(args, permissions);

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) => _runtime.execute(_inner, args);
}
