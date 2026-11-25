import '../persisted_task.dart';
import '../pet_tool.dart';
import '../task_store.dart';

/// 提醒工具：创建 / 列出 / 取消。任务落在 TaskStore，重启不丢。
///
/// 时间到点的「响铃」不是这个工具的事——Brain 的 TimerTrigger
/// 巡视到到期任务后主动汇报，这才是宠物「主动」的部分。
class ReminderTool extends PetTool {
  ReminderTool(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final TaskStore _store;
  final DateTime Function() _now;

  @override
  String get name => 'reminder';

  @override
  String get description =>
      '设置、查看或取消提醒。创建提醒需要 title（提醒内容）与 ISO8601 时间 at；'
      'repeat 为 "once" 或 "daily"。查看传 action="list"；取消传 action="cancel"，'
      '可用 keyword 按内容筛选，不传则取消全部。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['create', 'list', 'cancel'],
            'description': '默认 create',
          },
          'title': {'type': 'string', 'description': '提醒内容'},
          'at': {'type': 'string', 'description': 'ISO8601 时间，create 时必填'},
          'repeat': {'type': 'string', 'enum': ['once', 'daily']},
          'keyword': {'type': 'string', 'description': '取消时按内容筛选，可省略'},
        },
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = (args['action'] as String?)?.trim() ?? 'create';
    switch (action) {
      case 'list':
        return _list();
      case 'cancel':
        return _cancel((args['keyword'] as String?)?.trim());
      case 'create':
      default:
        return _create(args);
    }
  }

  Future<ToolResult> _create(Map<String, dynamic> args) async {
    final title = (args['title'] as String?)?.trim();
    final atRaw = (args['at'] as String?)?.trim();
    if (title == null || title.isEmpty || atRaw == null) {
      return const ToolResult.fail('创建提醒需要内容（title）和时间（at）。');
    }
    final at = DateTime.tryParse(atRaw);
    if (at == null) return const ToolResult.fail('时间格式不对，需要 ISO8601。');
    final repeat = args['repeat'] == 'daily' ? TaskRepeat.daily : TaskRepeat.once;

    final tasks = List<PersistedTask>.of(await _store.load());
    var effectiveAt = at;
    if (!effectiveAt.isAfter(_now())) {
      // 在线模型偶尔会把「明天」折成今天：过去的时间统一顺延一天兜底。
      if (repeat == TaskRepeat.daily || _now().difference(effectiveAt).inMinutes > 5) {
        while (!effectiveAt.isAfter(_now())) {
          effectiveAt = effectiveAt.add(const Duration(days: 1));
        }
      }
    }
    tasks.add(PersistedTask(
      id: 'reminder-${_now().millisecondsSinceEpoch}',
      kind: 'reminder',
      title: title,
      at: effectiveAt,
      repeat: repeat,
      createdAt: _now(),
    ));
    await _store.save(tasks);
    final when = repeat == TaskRepeat.daily ? '每天 ${_hhmm(effectiveAt)}' : _fmt(effectiveAt);
    return ToolResult.ok('好，$when 我会提醒你$title。');
  }

  Future<ToolResult> _list() async {
    final pending = (await _store.load()).where((task) => task.isScheduled).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (pending.isEmpty) return const ToolResult.ok('现在没有待办的提醒。');
    final lines = [
      for (final task in pending)
        '${task.repeat == TaskRepeat.daily ? "每天 " : ""}${_fmt(task.at)} · ${task.title}',
    ];
    return ToolResult.ok('待办的提醒有：\n${lines.join('\n')}');
  }

  Future<ToolResult> _cancel(String? keyword) async {
    final tasks = List<PersistedTask>.of(await _store.load());
    var cancelled = 0;
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (!task.isScheduled) continue;
      final hit = keyword == null ||
          keyword.isEmpty ||
          task.title.contains(keyword) ||
          keyword.contains(task.title);
      if (!hit) continue;
      tasks[i] = task.copyWith(status: TaskStatus.cancelled);
      cancelled++;
    }
    if (cancelled == 0) return ToolResult.fail('没有找到${keyword == null ? '' : '「$keyword」相关'}的提醒。');
    await _store.save(tasks);
    return ToolResult.ok('已取消 $cancelled 个提醒。');
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _fmt(DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final prefix = switch (diff) {
      0 => '今天',
      1 => '明天',
      2 => '后天',
      _ => '${t.month}月${t.day}日',
    };
    return '$prefix ${_hhmm(t)}';
  }
}
