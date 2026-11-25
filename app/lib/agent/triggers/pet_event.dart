import 'package:flutter/foundation.dart';

/// 事件来源。新增 Trigger 时在这里加枚举值。
enum PetEventSource { clipboard, appFocus, power, timer, gesture, speculative }

/// 一次「消息找活」的候选事件。
///
/// 经过两级过滤：
/// 1. 程序规则（Trigger 内部 + QuietHours）——已在发出前完成；
/// 2. 模型/规则判断是否值得行动——由 Brain 决定。
///
/// `payload` 只放**非敏感的摘要**：剪贴板事件放「检测到 URL / 英文句子」这种
/// 模式标签，不存原文（隐私要求见 super-agent-refactor.md §6）。
@immutable
class PetEvent {
  const PetEvent({
    required this.id,
    required this.source,
    required this.summary,
    this.payload = const {},
    required this.at,
  });

  final String id;
  final PetEventSource source;

  /// 一句话摘要，可直接喂给模型做二级判断。
  final String summary;

  /// 非敏感的结构化信息（模式标签、应用大类等），不得放原文。
  final Map<String, String> payload;

  final DateTime at;

  @override
  String toString() => 'PetEvent(${source.name}: $summary)';
}

/// Trigger 抽象 —— DSH「一切皆插件」的 Dart 版。
///
/// M5 起感知类 Trigger 默认启用（全权限方向）；关掉「环境感知」或一键急停后
/// `enabled` 变为 false，轮询内部直接跳过，不会持续产生事件。
abstract class PetTrigger {
  const PetTrigger();

  String get name;
  bool get enabled;

  /// 已经过第一级程序过滤的事件流。
  Stream<PetEvent> get events;

  void dispose();
}
