import 'package:flutter/foundation.dart';

/// 一行执行留痕（状态条的历史部分）。
@immutable
class ActivityLine {
  const ActivityLine({
    required this.at,
    required this.label,
    required this.ok,
    this.detail = '',
  });

  final DateTime at;
  final String label;
  final bool ok;
  final String detail;

  String get timeLabel =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// 智能体「此刻在干什么」的可观察状态。
///
/// 挂在 AppController 上，被 ToolRuntime（每次工具调用）和 AutonomyLoop
/// （目标推进）共同驱动；气泡、聊天窗口用 `AnimatedBuilder` 监听，
/// 所以执行状态是实时的，不用等 20 秒心跳刷新界面。
class AgentActivity extends ChangeNotifier {
  AgentActivity({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const int historyLimit = 40;
  static const Duration resultVisible = Duration(seconds: 25);

  String? _goalTitle;
  String _phase = 'idle'; // idle | planning | tool | result
  String? _tool;
  String _toolArgs = '';
  int _step = 0;
  int _stepLimit = 0;
  bool _busy = false;
  bool _lastOk = true;
  String _result = '';
  DateTime? _resultAt;
  final List<ActivityLine> _lines = [];

  /// 当前阶段：idle / planning / tool / result（供界面与测试读取）。
  String get phase => _phase;
  bool get busy => _busy;
  bool get lastOk => _lastOk;
  String? get goalTitle => _goalTitle;
  int get step => _step;
  int get stepLimit => _stepLimit;
  String? get currentTool => _tool;
  List<ActivityLine> get recent => List.unmodifiable(_lines);

  /// 气泡 / 状态条上的一行字；没有活动且上次结果已过期时返回 null。
  String? get statusLine {
    if (_busy) {
      final prefix = _goalTitle == null
          ? '正在处理'
          : '「${_clip(_goalTitle!, 16)}」第 ${_step + 1} 步';
      if (_tool != null && _tool!.isNotEmpty) {
        return '$prefix · ${_toolLabel(_tool!)}${_toolArgs.isEmpty ? '' : ' ${_clip(_toolArgs, 22)}'}';
      }
      return '$prefix · 正在规划…';
    }
    if (_resultAt != null &&
        _result.isNotEmpty &&
        _now().difference(_resultAt!) <= resultVisible) {
      return '${_lastOk ? '完成' : '失败'} · ${_clip(_result, 46)}';
    }
    return null;
  }

  /// 聊天窗口用的较完整状态（两行）。
  ({String title, String detail})? get statusDetail {
    final line = statusLine;
    if (line == null) return null;
    final title = _busy
        ? (_goalTitle == null ? '正在执行本机操作' : '正在推进目标')
        : (_lastOk ? '最近一次执行完成' : '最近一次执行失败');
    final detail = _goalTitle == null
        ? line
        : '${_clip(_goalTitle!, 30)} · $line';
    return (title: title, detail: detail);
  }

  void beginGoal(String title, {int maxSteps = 12}) {
    _goalTitle = title.trim();
    _phase = 'planning';
    _step = 0;
    _stepLimit = maxSteps;
    _tool = null;
    _toolArgs = '';
    _busy = true;
    _result = '';
    _resultAt = null;
    _push('目标开始：${_clip(_goalTitle!, 40)}', ok: true);
    notifyListeners();
  }

  void updateGoal({int? step, String? phase}) {
    if (_goalTitle == null) return;
    if (step != null) _step = step;
    if (phase != null) _phase = phase;
    _busy = true;
    notifyListeners();
  }

  void endGoal({required bool ok, required String summary}) {
    _phase = 'result';
    _tool = null;
    _toolArgs = '';
    _busy = false;
    _lastOk = ok;
    _result = summary;
    _resultAt = _now();
    _goalTitle = null;
    _push(ok ? '完成：$summary' : '失败：$summary', ok: ok);
    notifyListeners();
  }

  /// 单次工具调用：beginTool / endTool 成对出现。
  void beginTool(String tool, Map<String, dynamic> args, {String source = 'user'}) {
    _tool = tool;
    _toolArgs = _argsLabel(args);
    _phase = 'tool';
    _busy = true;
    _result = '';
    _resultAt = null;
    // 步数由 AutonomyLoop 明确推进；聊天里的工具调用不占目标步数。
    _push('调用 $_tool ${_clip(_toolArgs, 40)}（$source）', ok: true);
    notifyListeners();
  }

  void endTool({required bool ok, required String output}) {
    _tool = null;
    _toolArgs = '';
    _phase = _goalTitle == null ? 'result' : 'planning';
    _busy = _goalTitle != null;
    if (_goalTitle == null) {
      _lastOk = ok;
      _result = output;
      _resultAt = _now();
    }
    _push(ok ? '成功：$output' : '失败：$output', ok: ok);
    notifyListeners();
  }

  /// 聊天里的一步（无目标上下文）也可以单独显示。
  void note(String text, {bool ok = true}) {
    _push(text, ok: ok);
    notifyListeners();
  }

  void reset() {
    _goalTitle = null;
    _phase = 'idle';
    _tool = null;
    _toolArgs = '';
    _step = 0;
    _stepLimit = 0;
    _busy = false;
    _result = '';
    _resultAt = null;
    notifyListeners();
  }

  void _push(String label, {required bool ok}) {
    _lines.insert(0, ActivityLine(
      at: _now(),
      label: _clip(label.replaceAll(RegExp(r'\s+'), ' ').trim(), 140),
      ok: ok,
    ));
    if (_lines.length > historyLimit) _lines.removeRange(historyLimit, _lines.length);
  }

  static String _argsLabel(Map<String, dynamic> args) {
    for (final key in ['command', 'path', 'url', 'action', 'target', 'title', 'text']) {
      final value = args[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value.replaceAll(RegExp(r'\s+'), ' ');
    }
    return '';
  }

  static String _clip(String text, int limit) =>
      text.length <= limit ? text : '${text.substring(0, limit)}…';

  /// 工具名 → 中文短标签，状态条不暴露内部英文标识。
  static String _toolLabel(String tool) => switch (tool) {
        'run_command' => '执行命令',
        'process' => '查看进程',
        'launch' => '启动程序',
        'http_request' => '访问网络',
        'file_read' => '读文件',
        'file_write' => '写文件',
        'file_list' => '列目录',
        'file_search' => '搜文件',
        'file_delete' => '删文件',
        'window' => '窗口操作',
        'input' => '键鼠操作',
        'screenshot' => '截屏',
        'clipboard' => '读剪贴板',
        'clipboard_write' => '写剪贴板',
        'reminder' => '设置提醒',
        'pet_control' => '做个动作',
        _ => tool,
      };
}
