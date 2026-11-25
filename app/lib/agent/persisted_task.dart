import 'package:flutter/foundation.dart';

/// 任务重复方式。
enum TaskRepeat { once, daily }

/// 任务生命周期状态。
/// running = 异步工具执行中（M3），Watchdog 检测到超时会介入。
enum TaskStatus { scheduled, running, done, cancelled, expired, failed }

/// 持久化任务：目前只承载提醒（M1），后续 M2/M3 会加查询、感知类任务。
///
/// 「状态外置」是 Super-agent 存算分离思想在本项目的落法：
/// 执行循环就是 App 进程，但任务表落盘 shared_preferences，
/// 进程重启后 Brain 依据任务表恢复（到点的补发、每日的重排）。
@immutable
class PersistedTask {
  const PersistedTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.at,
    this.repeat = TaskRepeat.once,
    this.status = TaskStatus.scheduled,
    required this.createdAt,
    this.lastFiredAt,
    this.startedAt,
    this.attempts = 0,
    this.lastError,
  });

  final String id;
  final String kind; // 'reminder'
  final String title;
  final DateTime at; // 下一次触发时间
  final TaskRepeat repeat;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? lastFiredAt;

  /// Watchdog 用：异步执行开始时间、已尝试次数、最后一次错误。
  final DateTime? startedAt;
  final int attempts;
  final String? lastError;

  bool get isScheduled => status == TaskStatus.scheduled;
  bool get isRunning => status == TaskStatus.running;
  bool isDue(DateTime now) => isScheduled && !at.isAfter(now);

  PersistedTask copyWith({
    String? title,
    DateTime? at,
    TaskRepeat? repeat,
    TaskStatus? status,
    DateTime? lastFiredAt,
    DateTime? startedAt,
    int? attempts,
    String? lastError,
  }) {
    return PersistedTask(
      id: id,
      kind: kind,
      title: title ?? this.title,
      at: at ?? this.at,
      repeat: repeat ?? this.repeat,
      status: status ?? this.status,
      createdAt: createdAt,
      lastFiredAt: lastFiredAt ?? this.lastFiredAt,
      startedAt: startedAt ?? this.startedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  /// 每日任务触发后推进到下一天的同一时刻。
  PersistedTask advancedDaily() {
    assert(repeat == TaskRepeat.daily);
    return copyWith(at: at.add(const Duration(days: 1)), lastFiredAt: DateTime.now());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'at': at.toIso8601String(),
        'repeat': repeat.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (lastFiredAt != null) 'lastFiredAt': lastFiredAt!.toIso8601String(),
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (attempts > 0) 'attempts': attempts,
        if (lastError != null) 'lastError': lastError,
      };

  static PersistedTask fromJson(Map<String, dynamic> json) {
    return PersistedTask(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: json['title'] as String,
      at: DateTime.parse(json['at'] as String),
      repeat: TaskRepeat.values.firstWhere(
        (r) => r.name == json['repeat'],
        orElse: () => TaskRepeat.once,
      ),
      status: TaskStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => TaskStatus.scheduled,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastFiredAt: json['lastFiredAt'] == null
          ? null
          : DateTime.parse(json['lastFiredAt'] as String),
      startedAt: json['startedAt'] == null ? null : DateTime.parse(json['startedAt'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['lastError']?.toString(),
    );
  }
}
