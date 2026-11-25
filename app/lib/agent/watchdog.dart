import 'dart:async';

import 'package:flutter/foundation.dart';

import 'brain_host.dart';
import 'persisted_task.dart';
import 'task_store.dart';

/// Watchdog —— Super-agent 五大机制之一的轻量版。
///
/// 职责：定期巡视任务表，处理三类异常：
/// 1. **卡死**：running 状态超过 [stuckTimeout]（进程崩过、异步工具没回调）；
/// 2. **重试超限**：attempts >= [maxAttempts] 的任务标记 failed，不再无限重试；
/// 3. **错过的到期任务**：scheduled 且早已过期（超过 [missedGrace]）的标记 expired；
///    在宽限内的由 Brain 补报。
///
/// 所有判定都是确定性的、零模型成本；结果写回任务表并给宿主一句降级台词。
class Watchdog {
  Watchdog({
    required TaskStore store,
    required BrainHost host,
    DateTime Function()? now,
    Duration? tickInterval,
    this.stuckTimeout = const Duration(minutes: 2),
    this.maxAttempts = 3,
    this.missedGrace = const Duration(minutes: 30),
  })  : _store = store,
        _host = host,
        _now = now ?? DateTime.now,
        _tickInterval = tickInterval ?? const Duration(seconds: 30);

  final TaskStore _store;
  final BrainHost _host;
  final DateTime Function() _now;
  final Duration _tickInterval;

  final Duration stuckTimeout;
  final int maxAttempts;
  final Duration missedGrace;

  Timer? _timer;
  bool _busy = false;

  /// 巡视结果，供测试与日志用。
  final List<WatchdogAction> actions = [];

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) => unawaited(patrolOnce()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// 手动巡视一次（测试缝 / Brain tick 联动）。
  Future<List<WatchdogAction>> patrolOnce() async {
    if (_busy) return const [];
    _busy = true;
    final now = _now();
    final found = <WatchdogAction>[];
    try {
      final tasks = List<PersistedTask>.of(await _store.load());
      var changed = false;
      for (var i = 0; i < tasks.length; i++) {
        final task = tasks[i];
        final action = inspect(task, now);
        if (action == null) continue;
        found.add(action);
        tasks[i] = switch (action.kind) {
          WatchdogActionKind.stuck => task.copyWith(
              status: TaskStatus.failed,
              lastError: '执行超时（${stuckTimeout.inSeconds}s）',
              startedAt: null,
            ),
          WatchdogActionKind.retryLimit => task.copyWith(status: TaskStatus.failed, startedAt: null),
          WatchdogActionKind.expired => task.copyWith(status: TaskStatus.expired),
        };
        changed = true;
        debugPrint('[watchdog] ${action.kind.name}: ${task.title} — ${action.message}');
      }
      if (changed) await _store.save(tasks);
      if (found.isNotEmpty && _host.agentPetMode) {
        // 只报一次汇总，避免连续失败时宠物刷屏。
        _host.agentBubble('有 ${found.length} 件事没做成，我已经记下来了，稍后再试。');
      }
      actions.addAll(found);
      if (actions.length > 50) actions.removeRange(0, actions.length - 50);
    } finally {
      _busy = false;
    }
    return found;
  }

  /// 纯判定函数：给一个任务和一个时间点，返回该介入的动作或 null。
  WatchdogAction? inspect(PersistedTask task, DateTime now) {
    if (task.isRunning) {
      final started = task.startedAt ?? task.createdAt;
      if (now.difference(started) >= stuckTimeout) {
        return WatchdogAction(
          kind: WatchdogActionKind.stuck,
          taskId: task.id,
          message: '卡住超过 ${stuckTimeout.inMinutes} 分钟，已降级',
        );
      }
      return null;
    }
    if (task.attempts >= maxAttempts) {
      return WatchdogAction(
        kind: WatchdogActionKind.retryLimit,
        taskId: task.id,
        message: '重试 $maxAttempts 次仍失败，已放弃',
      );
    }
    if (task.isScheduled && task.at.isBefore(now.subtract(missedGrace))) {
      return WatchdogAction(
        kind: WatchdogActionKind.expired,
        taskId: task.id,
        message: '错过超过 ${missedGrace.inMinutes} 分钟，不再补报',
      );
    }
    return null;
  }
}

enum WatchdogActionKind { stuck, retryLimit, expired }

@immutable
class WatchdogAction {
  const WatchdogAction({required this.kind, required this.taskId, required this.message});

  final WatchdogActionKind kind;
  final String taskId;
  final String message;

  @override
  String toString() => 'WatchdogAction(${kind.name}: $taskId — $message)';
}
