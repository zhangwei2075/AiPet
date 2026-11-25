import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pet.dart';
import 'audit_log.dart';
import 'autonomy.dart';
import 'brain_host.dart';
import 'memory/memory_service.dart';
import 'offline_intent.dart';
import 'persisted_task.dart';
import 'pet_tool.dart';
import 'task_store.dart';
import 'tool_probe.dart';
import 'tool_runtime.dart';
import 'tools/basic_tools.dart';
import 'tools/desktop_tools.dart';
import 'tools/file_tools.dart';
import 'tools/reminder_tool.dart';
import 'tools/system_tools.dart';
import 'watchdog.dart';

/// Brain（Super-agent 里的 Router，宠物版）。
///
/// 职责边界：
/// · 接三层输入——用户聊天文本（意图判定）、自主目标循环、TimerTrigger 心跳；
/// · 全局上下文（人格、当前形态）由宿主提供，Brain 不持有宠物状态；
/// · M5 起所有工具（含本机全权限工具）统一经 ToolRuntime 注册，权限与审计不漏入口；
/// · 任务执行即「触发→汇报→记账」，串行即可，不引入并发 Worker。
class PetBrain {
  PetBrain({
    required BrainHost host,
    required TaskStore store,
    ToolProbe? probe,
    MemoryService? memoryService,
    ToolRuntime? runtime,
    AutonomyLoop? loop,
    DateTime Function()? now,
  })  : _host = host,
        _store = store,
        _probe = probe,
        _memory = memoryService,
        _runtime = runtime ?? ToolRuntime(),
        _loop = loop,
        _now = now ?? DateTime.now {
    _registerTools();
  }

  void _registerTools() {
    // 一个入口都不漏：连 M1 的老工具也过一遍权限/审计装饰。
    void add(PetTool tool) => registry.register(_runtime.wrap(tool));
    add(ReminderTool(_store, now: _now));
    add(const ClipboardTool());
    add(PetControlTool(_host));
    for (final tool in buildSystemTools()) {
      add(tool);
    }
    for (final tool in buildFileTools()) {
      add(tool);
    }
    for (final tool in buildDesktopTools()) {
      add(tool);
    }
  }

  final BrainHost _host;
  final TaskStore _store;
  final ToolProbe? _probe;
  final DateTime Function() _now;
  final ToolRuntime _runtime;
  AutonomyLoop? _loop;

  final ToolRegistry registry = ToolRegistry();
  final MemoryService? _memory;

  /// 宿主先建 Brain（注册工具），再用注册表建 AutonomyLoop，最后挂回来，
  /// 避免「Brain 要 loop / loop 要 registry」的循环依赖（同 attachWatchdog 的做法）。
  void attachLoop(AutonomyLoop loop) => _loop = loop;

  /// 设置页读权限/审计用的运行时。
  ToolRuntime get runtime => _runtime;

  /// 在线单工具探测器保留在 Brain 上（自主循环用同一实例的 plan；
  /// 聊天主通道已改由 ChatAgent 承担多轮工具调用）。
  ToolProbe? get probe => _probe;

  /// 设置页查看目标队列用。
  AutonomyLoop? get loop => _loop;
  Timer? _ticker;
  bool _busy = false;

  /// 异步任务表：超过 [asyncThreshold] 的工具调用转后台，完成后汇报。
  /// M3 的「等待不阻塞」——宠物说「我去看看」，聊天流立刻恢复。
  final Map<String, Future<ToolResult>> _runningTasks = {};
  Watchdog? _watchdog;

  static const Duration asyncThreshold = Duration(seconds: 5);

  /// 连接 Watchdog（由宿主装配，避免循环依赖）。
  void attachWatchdog(Watchdog watchdog) => _watchdog = watchdog;

  /// Watchdog 巡视结果（设置页/测试可查）。
  List<WatchdogAction> get watchdogActions => _watchdog?.actions ?? const [];

  /// 当前后台任务数（设置页 / 测试可查）。
  int get runningTaskCount => _runningTasks.length;

  /// 错过多久以内的到期提醒仍然补报（再早就标记过期，不吓人）。
  static const Duration missedGrace = Duration(minutes: 30);

  /// 巡视周期。
  static const Duration tickInterval = Duration(seconds: 20);

  // ---------------------------------------------------------------- 生命周期

  /// App 启动时调用：恢复任务表，错过的按宽限补报。
  Future<void> start() async {
    final now = _now();
    final tasks = await _store.load();
    var changed = false;
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (!task.isScheduled || !task.at.isBefore(now)) continue;
      if (now.difference(task.at) <= missedGrace) {
        tasks[i] = await _fire(task, missed: true);
      } else {
        tasks[i] = task.copyWith(status: TaskStatus.expired);
        debugPrint('[brain] 任务过期：${task.title}（${task.at}）');
      }
      changed = true;
    }
    if (changed) await _store.save(_compact(tasks));
    _ticker = Timer.periodic(tickInterval, (_) => unawaited(_onTick()));
    // 重启后未做完的目标立刻续跑，不必等第一个 20 秒心跳。
    unawaited(_loop?.tick());
  }

  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _loop?.dispose();
  }

  /// 测试缝：手动执行一次到期巡视（真实定时器由 start() 驱动）。
  Future<void> handleTickForTest() => _onTick();

  /// 记忆归属的宠物 id（宿主提供；单宠物场景就是当前激活宠物）。
  String get petIdOfContext => _host.agentPetId;

  // ---------------------------------------------------------------- 用户文本

  /// 聊天文本的意图判定入口。
  /// 返回 null = 不是工具意图，调用方走普通聊天；否则返回要回复的话。
  Future<BrainReply?> handleUserText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1) 本地规则（确定性，0 成本）：提醒 / 宠物动作 / 剪贴板。
    var intent = parseOfflineIntent(text, _now());

    // 1.5) 离线本机操作路由：默认聊天后端就是本地小脑，没有在线模型时，
    // 这一步是「通过对话操作电脑」的主通道——文件、命令、进程、窗口、
    // 截屏、网址都能立刻执行，不用等 20 秒心跳，也不用模型。
    // 在线时跳过：交给 ChatAgent 的多步 ReAct，模型能处理更复杂的组合。
    if (intent == null && !_host.agentOnlineAvailable) {
      final action = parseOfflineAction(text);
      if (action != null && registry.lookup(action.tool) != null) {
        // 本机工具都声明为 slow，但对话里主人要的是「说完就看到结果」：
        // 这里直接走同步通用通道，不让结果只落到后台气泡里。
        intent = GenericToolIntent(tool: action.tool, args: action.args);
      }
    }

    // 2) 在线聊天不再走一次性的 ToolProbe.probe：那会让一句话先打一次探测、
    //    再打一次聊天，且只能执行单步。现在在线统一交给 ChatAgent 的多轮
    //    function calling 回路（见 chat_agent.dart），Brain 只保留确定性规则。
    //    ToolProbe 仍被自主循环用于多步规划。

    // 3) 离线兜底：规则接不住、但确实像一桩待办 → 交给自主循环拆解。
    // 在线时不再截断聊天，ChatAgent 会在同一轮里多步执行。
    if (intent == null &&
        !_host.agentOnlineAvailable &&
        _loop != null &&
        _host.agentSettings.autonomyEnabled &&
        !_runtime.permissions.paused &&
        looksLikeCommand(text)) {
      return BrainReply(await _loop!.submit(text), PetMood.talk);
    }
    if (intent == null) return null;

    // M3：耗时工具转后台。判定依据是工具声明的 `slow` 标记（见 basic_tools），
    // 不是猜时间——本机提醒必须即时确认，网络查询才该「我去看看」。
    if (intent case SlowToolIntent(:final tool, :final args, :final prompt)) {
      return _startBackgroundTool(tool, args, prompt);
    }
    return await _replyFor(intent);
  }

  /// 后台工具：立刻回一句，真正执行不阻塞聊天流。
  BrainReply _startBackgroundTool(String toolName, Map<String, dynamic> args, String prompt) {
    final id = 'tool-${_now().microsecondsSinceEpoch}';
    final task = PersistedTask(
      id: id,
      kind: toolName,
      title: prompt,
      at: _now(),
      createdAt: _now(),
      status: TaskStatus.running,
      startedAt: _now(),
      attempts: 1,
    );
    unawaited(_store.load().then((tasks) => _store.save([...tasks, task])));

    final future = registry.lookup(toolName)?.invoke(args) ??
        Future.value(ToolResult.fail('工具 $toolName 没有注册'));
    _runningTasks[id] = future;
    future.then((result) async {
      _runningTasks.remove(id);
      final tasks = await _store.load();
      final updated = tasks.map((t) => t.id == id
          ? t.copyWith(
              status: result.success ? TaskStatus.done : TaskStatus.failed,
              lastFiredAt: _now(),
              lastError: result.success ? null : result.message,
            )
          : t).toList();
      await _store.save(updated);
      final line = result.success ? '查好了：$prompt — ${result.message}' : '没查成：${result.message}';
      if (_host.agentPetMode) _host.agentBubble(line);
      _host.agentSpeak(line);
    }).catchError((error) async {
      _runningTasks.remove(id);
      final tasks = await _store.load();
      await _store.save(tasks.map((t) => t.id == id
          ? t.copyWith(status: TaskStatus.failed, lastError: error.toString())
          : t).toList());
      debugPrint('[brain] 后台工具失败: $error');
    });
    return BrainReply(prompt, PetMood.talk);
  }

  /// 所有分支都 await 完成：回复文案反映的是已执行完的结果，
  /// 聊天面板与桌面气泡两种形态看到的内容一致。
  Future<BrainReply> _replyFor(AgentIntent intent) async {
    switch (intent) {
      case ReminderIntent(:final title, :final at, :final daily):
        await _createReminder(title: title, at: at, daily: daily);
        final when = daily ? '每天 ${_hhmm(at)}' : _fmt(at);
        return BrainReply('好，$when 我会提醒你$title。', PetMood.happy);
      case ReminderNeedsTimeIntent():
        return const BrainReply('想让我提醒你什么呢？告诉我时间，比如「15:30 提醒我喝水」。', PetMood.talk);
      case CancelRemindersIntent(:final keyword):
        final cancelled = await _cancelReminders(keyword);
        if (cancelled == 0) {
          return BrainReply('没有找到${keyword == null ? '' : '「$keyword」相关'}的提醒。', PetMood.talk);
        }
        return BrainReply(
          keyword == null ? '好，$cancelled 个提醒都清掉了。' : '好，「$keyword」相关的提醒取消了。',
          PetMood.happy,
        );
      case ListRemindersIntent():
        return BrainReply(await _listReminders(), PetMood.talk);
      case PetControlIntent(:final action):
        _performControl(action);
        return BrainReply(_controlLine(action), PetMood.happy);
      case ClipboardReadIntent():
        final result = await registry.lookup('clipboard')!.invoke({});
        return BrainReply(result.message, PetMood.talk);
      case GenericToolIntent(:final tool, :final args):
        // M5 通用执行通道：任意注册工具（本机命令、文件、窗口、键鼠……）
        // 都能被模型点名执行，能力校验与审计由 ToolRuntime 的包装层完成。
        final registered = registry.lookup(tool);
        if (registered == null) return BrainReply('工具 $tool 还没注册。', PetMood.talk);
        final result = await registered.invoke(args);
        return BrainReply(
          truncate(result.message, 600),
          result.success ? PetMood.happy : PetMood.talk,
        );
      case SlowToolIntent():
        // 理论上在 handleUserText 里已拦截；这里兜底避免编译期穷尽性漏洞。
        return const BrainReply('好嘞，我去看看，稍等一下。', PetMood.talk);
    }
  }

  /// 主人或 UI 直接下达一个复杂目标，交给自主循环在后台推进。
  Future<String> submitGoal(String title) async {
    final loop = _loop;
    if (loop == null) return '自主执行还没启用，先去「智能体 → 权限」打开。';
    return loop.submit(title);
  }

  // ---------------------------------------------------------------- 任务执行
  //
  // 模型点名工具的参数转换曾放在 `_executeIntent`（reminder / pet_control /
  // clipboard 三类硬编码映射）。M5.1 起聊天统一由 ChatAgent 按工具 schema
  // 直接调用，Brain 只保留确定性规则与离线动作路由，那段映射已删除。

  Future<void> _createReminder({required String title, required DateTime at, required bool daily}) async {
    final tasks = List<PersistedTask>.of(await _store.load());
    final when = daily ? '每天 ${_hhmm(at)}' : _fmt(at);
    _memory?.recordTask(petIdOfContext, '主人设了一个提醒：$title（$when）');
    tasks.add(PersistedTask(
      id: 'reminder-${_now().millisecondsSinceEpoch}',
      kind: 'reminder',
      title: title,
      at: at,
      repeat: daily ? TaskRepeat.daily : TaskRepeat.once,
      createdAt: _now(),
    ));
    await _store.save(tasks);
  }

  Future<int> _cancelReminders(String? keyword) async {
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
    if (cancelled > 0) await _store.save(tasks);
    return cancelled;
  }

  Future<String> _listReminders() async {
    final pending = (await _store.load()).where((task) => task.isScheduled).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (pending.isEmpty) return '现在没有待办的提醒。';
    return '待办的提醒：\n'
        '${[
      for (final task in pending)
        '· ${task.repeat == TaskRepeat.daily ? "每天 " : ""}${_fmt(task.at)} ${task.title}',
    ].join('\n')}';
  }

  void _performControl(PetControlAction action) {
    switch (action) {
      case PetControlAction.stroll:
        _host.agentStroll(run: false);
      case PetControlAction.run:
        _host.agentStroll(run: true);
      case PetControlAction.hop:
        _host.agentHop();
      case PetControlAction.sleep:
        _host.agentSleep();
      case PetControlAction.wake:
        _host.agentWake();
      case PetControlAction.beg:
        _host.agentBeg();
    }
  }

  String _controlLine(PetControlAction action) => switch (action) {
        PetControlAction.stroll => '好嘞，出去溜达一圈！',
        PetControlAction.run => '汪！冲啦——',
        PetControlAction.hop => '看我的弹簧腿！',
        PetControlAction.sleep => '那我先眯一会儿……Zzz',
        PetControlAction.wake => '哈——我醒着呢！',
        PetControlAction.beg => '咕噜咕噜……要摸摸。',
      };

  // ---------------------------------------------------------------- 到期巡视

  Future<void> _onTick() async {
    if (_busy) return; // 上一轮还没收尾就跳过，天然串行
    _busy = true;
    try {
      final now = _now();
      final tasks = await _store.load();
      var changed = false;
      for (var i = 0; i < tasks.length; i++) {
        final task = tasks[i];
        if (!task.isDue(now)) continue;
        tasks[i] = await _fire(task);
        changed = true;
      }
      // 统一在这里保存，避免和 _fire 各写一份造成快照互相覆盖
      if (changed) await _store.save(_compact(tasks));
      unawaited(_memory?.dailyRollIfNeeded(petIdOfContext, settings: _host.agentSettings));
      // M5：自主目标循环由同一心跳驱动，后台串行、不阻塞提醒巡视。
      unawaited(_loop?.tick());
    } catch (error) {
      debugPrint('[brain] tick failed: $error');
    } finally {
      _busy = false;
    }
  }

  /// 触发一个到期任务：汇报 + 返回更新后的任务（once 完成、daily 顺延）。
  /// 落盘由调用方统一负责，这里只做纯计算，避免快照互相覆盖。
  Future<PersistedTask> _fire(PersistedTask task, {bool missed = false}) async {
    final prefix = missed ? '刚才没在，补个提醒：' : '叮！时间到：';
    final text = '$prefix${task.title}';
    if (_host.agentPetMode) {
      _host.agentBubble(text, mood: PetMood.happy);
      _host.agentHop();
    }
    _host.agentSpeak(text);

    return task.repeat == TaskRepeat.daily
        ? task.copyWith(at: task.at.add(const Duration(days: 1)), lastFiredAt: _now())
        : task.copyWith(status: TaskStatus.done, lastFiredAt: _now());
  }

  /// 清掉已终结的任务，防止表无限增长（保留最近 50 条防抖）。
  List<PersistedTask> _compact(List<PersistedTask> tasks) {
    final finished = tasks.where((t) => !t.isScheduled).toList();
    final keep = finished.length > 50 ? finished.sublist(finished.length - 50) : finished;
    return [...tasks.where((t) => t.isScheduled), ...keep];
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

/// Brain 给聊天层的回复：文案 + 建议情绪。
class BrainReply {
  const BrainReply(this.text, this.mood);

  final String text;
  final PetMood mood;
}
