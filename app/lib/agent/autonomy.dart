import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';
import '../models/settings.dart';
import 'activity.dart';
import 'audit_log.dart';
import 'brain_host.dart';
import 'experience.dart';
import 'memory/memory_service.dart';
import 'offline_intent.dart';
import 'permissions.dart';
import 'pet_tool.dart';
import 'tool_probe.dart';
import 'tool_runtime.dart';

/// 目标状态机：
/// ```
/// queued ──tick──▶ running ──PlanToolCall──▶ running（继续下一步）
///                     ├──PlanFinish────────▶ done
///                     └──PlanFail / 熔断───▶ failed
/// 任意活动态 ──cancel()──────────────────▶ cancelled
/// ```
enum GoalStatus { queued, running, done, failed, cancelled }

/// 自主循环里已经执行过的一步。参数与输出都只存摘要，不留原文。
@immutable
class GoalStep {
  const GoalStep({
    required this.tool,
    required this.argsSummary,
    required this.ok,
    required this.output,
    required this.at,
  });

  final String tool;
  final String argsSummary;
  final bool ok;
  final String output;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'argsSummary': argsSummary,
        'ok': ok,
        'output': output,
        'at': at.toIso8601String(),
      };

  factory GoalStep.fromJson(Map<String, dynamic> json) => GoalStep(
        tool: json['tool']?.toString() ?? '',
        argsSummary: json['argsSummary']?.toString() ?? '',
        ok: json['ok'] == true,
        output: json['output']?.toString() ?? '',
        at: DateTime.tryParse(json['at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

@immutable
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.origin,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.steps = const [],
    this.lastError,
    this.maxSteps = 12,
  });

  final String id;
  final String title;

  /// 'user' = 主人吩咐，'self' = 智能体空闲时自己发起的只读巡检。
  final String origin;
  final GoalStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GoalStep> steps;
  final String? lastError;
  final int maxSteps;

  bool get active => status == GoalStatus.queued || status == GoalStatus.running;

  Goal copyWith({
    String? title,
    String? origin,
    GoalStatus? status,
    DateTime? updatedAt,
    List<GoalStep>? steps,
    String? lastError,
    int? maxSteps,
  }) =>
      Goal(
        id: id,
        title: title ?? this.title,
        origin: origin ?? this.origin,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        steps: steps ?? this.steps,
        lastError: lastError ?? this.lastError,
        maxSteps: maxSteps ?? this.maxSteps,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'origin': origin,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'steps': [for (final step in steps) step.toJson()],
        if (lastError != null) 'lastError': lastError,
        'maxSteps': maxSteps,
      };

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        origin: json['origin']?.toString() ?? 'user',
        status: GoalStatus.values.firstWhere(
          (s) => s.name == json['status']?.toString(),
          orElse: () => GoalStatus.queued,
        ),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        steps: [
          for (final item in (json['steps'] as List?) ?? const [])
            GoalStep.fromJson((item as Map).cast<String, dynamic>()),
        ],
        lastError: json['lastError']?.toString(),
        maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 12,
      );
}

/// 目标队列持久化：重启后没做完的目标继续跑（Super-agent「状态外置」）。
class GoalStore {
  GoalStore({SharedPreferences? prefs, String key = prefsKey})
      : _prefs = prefs,
        _key = key;

  static const String prefsKey = 'agent.goals.v1';

  SharedPreferences? _prefs;
  final String _key;

  Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<Goal>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Goal>[];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          Goal.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return <Goal>[];
    }
  }

  Future<void> save(List<Goal> goals) async {
    final prefs = await _instance();
    await prefs.setString(_key, jsonEncode([for (final g in goals) g.toJson()]));
  }
}

/// 空闲自驱的只读巡检清单。刻意全部只读：自己找活干，绝不自己动主人的数据。
const List<String> selfDriveGoals = [
  '检查这台电脑各磁盘的剩余空间，只有占用超过 90% 才需要提醒主人',
  '列出当前占用内存最多的前 10 个进程，发现异常再提醒',
  '查看工作区 D:/AiPet 最近一天修改过的文件，给一句话摘要',
  '查看系统启动时间与当前登录用户，确认运行环境正常',
];

/// 离线降级规划：没有在线模型时，把目标映射成一次工具调用。
///
/// 直接复用 [parseOfflineAction] 的规则表，避免两处各维护一套关键词；
/// 规则接不住时再退到只读巡检兜底。离线只做一步，不假装完成多步任务。
/// 纯函数，单测直接覆盖。
PlanDecision offlinePlan(String goal, String history) {
  if (history.trim().isNotEmpty) {
    return const PlanFinish('离线模式完成了一次本机检查。');
  }
  final action = parseOfflineAction(goal);
  if (action != null) {
    return PlanToolCall(action.tool, action.args);
  }
  final text = goal.toLowerCase();
  if (text.contains('磁盘') || text.contains('空间') || text.contains('disk')) {
    return const PlanToolCall('run_command', {
      'command': 'Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free',
    });
  }
  if (text.contains('进程') || text.contains('内存')) {
    return const PlanToolCall('process', {'action': 'list'});
  }
  if (text.contains('文件') || text.contains('目录') || text.contains('工作区')) {
    return const PlanToolCall('file_list', {'path': 'D:/AiPet', 'recursive': false, 'limit': 40});
  }
  if (text.contains('窗口') || text.contains('前台')) {
    return const PlanToolCall('window', {'action': 'list'});
  }
  return const PlanFail('离线状态无法做多步规划，请接一个 OpenAI 兼容模型。');
}

/// 自主循环（M5）：目标 → 规划 → 工具 → 复盘 → 继续/结束。
///
/// 由 Brain 的 20 秒心跳驱动，也可用 [submit] 立即推一步。整个过程在后台串行执行，
/// 不阻塞聊天；每一步都经 [ToolRuntime] 做权限校验与审计，来源标记为 `goal`。
class AutonomyLoop {
  AutonomyLoop({
    required BrainHost host,
    required ToolRegistry registry,
    required ToolRuntime runtime,
    required GoalStore store,
    required ToolProbe probe,
    required bool Function() isEnabled,
    required AppSettings Function() settings,
    bool Function()? onlineAvailable,
    AgentPermissions Function()? permissions,
    MemoryService? memory,
    AgentActivity? activity,
    ExperienceBank? experience,
    DateTime Function()? now,
  })  : _host = host,
        _registry = registry,
        _runtime = runtime,
        _store = store,
        _probe = probe,
        _isEnabled = isEnabled,
        _settings = settings,
        _onlineAvailable = onlineAvailable ?? (() => host.agentOnlineAvailable),
        _permissions = permissions ?? (() => runtime.permissions),
        _memory = memory,
        _activity = activity,
        _experience = experience,
        _now = now ?? DateTime.now;

  final BrainHost _host;
  final ToolRegistry _registry;
  final ToolRuntime _runtime;
  final GoalStore _store;
  final ToolProbe _probe;
  final bool Function() _isEnabled;
  final AppSettings Function() _settings;
  final bool Function() _onlineAvailable;
  final AgentPermissions Function() _permissions;
  final MemoryService? _memory;
  final AgentActivity? _activity;
  final ExperienceBank? _experience;
  final DateTime Function() _now;

  bool _busy = false;
  bool _disposed = false;
  DateTime? _lastSelfDrive;
  int _selfDriveCursor = 0;

  /// 交给主人一句即时回执；真正的执行在后台。
  Future<String> submit(String title, {String origin = 'user'}) async {
    final clean = title.trim();
    // 拷一份再改：load() 在空库/解析失败时返回的是不可变列表。
    final goals = [...await _store.load()];
    final goal = Goal(
      id: 'goal-${_now().microsecondsSinceEpoch}',
      title: clean.isEmpty ? '未命名目标' : clean,
      origin: origin,
      status: GoalStatus.queued,
      createdAt: _now(),
      updatedAt: _now(),
      maxSteps: _permissions().maxStepsPerGoal,
    );
    goals.add(goal);
    await _store.save(_compact(goals));
    if (!goals.any((g) => g.active && g.id != goal.id)) {
      _activity?.beginGoal(goal.title, maxSteps: goal.maxSteps);
    }
    unawaited(tick()); // 不必等下一个 20 秒心跳
    return origin == 'user'
        ? '收到，我来处理「${goal.title}」，做完告诉你。'
        : '我自己去看一下：${goal.title}';
  }

  Future<List<Goal>> goals() => _store.load();

  Future<void> cancel(String id) async {
    final goals = await _store.load();
    final index = goals.indexWhere((g) => g.id == id);
    if (index < 0 || !goals[index].active) return;
    final title = goals[index].title;
    goals[index] = goals[index].copyWith(
      status: GoalStatus.cancelled,
      updatedAt: _now(),
    );
    await _store.save(goals);
    if (_activity?.goalTitle == title) {
      _activity?.endGoal(ok: false, summary: '目标已取消：${truncate(title, 60)}');
    }
  }

  /// 心跳调用：一次只推进一步，天然串行，不会因为模型慢而堆一窝并发子进程。
  Future<void> tick() async {
    if (_disposed || _busy || !_isEnabled()) return;
    _busy = true;
    try {
      final goals = await _store.load();
      final index = goals.indexWhere((g) => g.active);
      if (index < 0) {
        await _maybeSelfDrive(goals);
        return;
      }
      final current = goals[index];
      // 重启续跑 / 自驱目标没有走过 submit，这里补上状态跟踪。
      if (_activity?.goalTitle != current.title) {
        _activity?.beginGoal(current.title, maxSteps: current.maxSteps);
      }
      goals[index] = await _step(current);
      await _store.save(_compact(goals));
    } catch (error) {
      debugPrint('[autonomy] tick failed: $error');
    } finally {
      _busy = false;
    }
  }

  Future<Goal> _step(Goal goal) async {
    final now = _now();
    final running = goal.copyWith(status: GoalStatus.running, updatedAt: now);
    _activity?.updateGoal(step: running.steps.length, phase: 'planning');
    if (running.steps.length >= running.maxSteps) {
      return _finish(running, GoalStatus.failed, '步数已达上限 ${running.maxSteps}，先停一下。');
    }
    if (_consecutiveFailures(running.steps) >= 2) {
      return _finish(running, GoalStatus.failed, '连续两次工具失败，不再重试。');
    }

    final history = _historyOf(running);
    // 先召回同类目标的既往经验，让规划「越用越会」；失败不影响本步。
    final lessons = _experience == null
        ? ''
        : await _experience.recallForPrompt(running.title);
    final decision = _onlineAvailable()
        ? await _probe.plan(
            goal: running.title,
            // 在线规划需要「这是第一步」的提示；离线规划用空串表示第一步，
            // 两者不能共用同一个占位文案，否则 offlinePlan 会误判成已经做过一步。
            history: history.isEmpty ? '（第一步，尚无执行记录）' : history,
            settings: _settings(),
            tools: _registry.all,
            experience: lessons,
          )
        : offlinePlan(running.title, history);

    switch (decision) {
      case PlanToolCall(:final tool, :final args):
        final registered = _registry.lookup(tool);
        late final ToolResult result;
        if (registered == null) {
          result = ToolResult.fail('工具 $tool 没有注册');
        } else {
          result = await _runtime.executeTracked(registered, args, source: 'goal');
        }
        final step = GoalStep(
          tool: tool,
          argsSummary: summarizeArgs(args, limit: 200),
          ok: result.success,
          output: truncate(result.message.replaceAll(RegExp(r'\s+'), ' ').trim(), 500),
          at: _now(),
        );
        final updated = running.copyWith(
          steps: [...running.steps, step],
          updatedAt: _now(),
        );
        if (_consecutiveFailures(updated.steps) >= 2) {
          return _finish(updated, GoalStatus.failed, '连续两次工具失败，不再重试。');
        }
        // 每两步给一句进度，别刷屏。
        if (updated.steps.length % 2 == 0 && _host.agentPetMode) {
          _host.agentBubble('「${updated.title}」进行到第 ${updated.steps.length} 步…');
        }
        return updated;

      case PlanFinish(:final summary):
        return _finish(running, GoalStatus.done, summary);

      case PlanFail(:final reason):
        return _finish(running, GoalStatus.failed, reason);
    }
  }

  Goal _finish(Goal goal, GoalStatus status, String note) {
    final text = truncate(note.replaceAll(RegExp(r'\s+'), ' ').trim(), 300);
    final line = status == GoalStatus.done
        ? '搞定啦：${goal.title} — $text'
        : '这件事没办成：${goal.title} — $text';
    if (_host.agentPetMode) {
      _host.agentBubble(line, mood: status == GoalStatus.done ? PetMood.happy : PetMood.talk);
    }
    _host.agentSpeak(line);
    _memory?.recordTask(
      _host.agentPetId,
      '目标「${goal.title}」${status == GoalStatus.done ? '完成' : '失败'}：$text',
      tag: 'goal',
    );
    _activity?.endGoal(ok: status == GoalStatus.done, summary: text);
    unawaited(_recordExperience(goal, status, text));
    return goal.copyWith(
      status: status,
      updatedAt: _now(),
      lastError: status == GoalStatus.failed ? text : null,
    );
  }

  /// 目标级复盘：记下「这类事用了哪几个工具、做成没有、结论是什么」，
  /// 下次聊天 / 规划时由 ExperienceBank 召回注入 prompt。
  Future<void> _recordExperience(Goal goal, GoalStatus status, String note) async {
    try {
      await _experience?.record(
        goal: goal.title,
        ok: status == GoalStatus.done,
        tools: [for (final step in goal.steps) step.tool],
        summary: note,
        origin: goal.origin,
      );
    } catch (_) {
      // 经验写盘失败绝不影响目标本身。
    }
  }

  /// 队列空了就自己找一件只读的事做，节流由 `selfDriveIntervalMinutes` 控制。
  Future<void> _maybeSelfDrive(List<Goal> goals) async {
    final permissions = _permissions();
    if (permissions.selfDriveIntervalMinutes <= 0 || !_onlineAvailable()) return;
    final now = _now();
    final last = _lastSelfDrive;
    if (last != null &&
        now.difference(last) < Duration(minutes: permissions.selfDriveIntervalMinutes)) {
      return;
    }
    if (goals.any((g) => g.origin == 'self' && g.active)) return;
    _lastSelfDrive = now;
    final title = selfDriveGoals[_selfDriveCursor++ % selfDriveGoals.length];
    goals.add(Goal(
      id: 'goal-self-${now.microsecondsSinceEpoch}',
      title: title,
      origin: 'self',
      status: GoalStatus.queued,
      createdAt: now,
      updatedAt: now,
      maxSteps: 3, // 自驱巡检刻意限制步数，别自己越跑越远
    ));
    await _store.save(_compact(goals));
  }

  String _historyOf(Goal goal) {
    // 空串 = 第一步。offlinePlan 以此判断是否还能再执行一个只读工具。
    if (goal.steps.isEmpty) return '';
    return [
      for (var i = 0; i < goal.steps.length; i++)
        '${i + 1}. ${goal.steps[i].tool} ${goal.steps[i].argsSummary} '
            '→ ${goal.steps[i].ok ? '成功' : '失败'}：${goal.steps[i].output}',
    ].join('\n');
  }

  int _consecutiveFailures(List<GoalStep> steps) {
    var count = 0;
    for (final step in steps.reversed) {
      if (step.ok) break;
      count++;
    }
    return count;
  }

  /// 只保留最近 50 个已终结目标，防止队列无限增长。
  List<Goal> _compact(List<Goal> goals) {
    final active = goals.where((g) => g.active).toList();
    final finished = goals.where((g) => !g.active).toList();
    final keep = finished.length > 50 ? finished.sublist(finished.length - 50) : finished;
    return [...active, ...keep];
  }

  void dispose() => _disposed = true;
}
