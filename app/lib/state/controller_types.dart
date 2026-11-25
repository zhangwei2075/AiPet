/// 状态中枢对外暴露的枚举。单独成库，避免各 coordinator 与
/// `app_controller.dart` 互相 import（循环依赖）。
library;

/// 点击 / 聊天时冒出的粒子类型。
enum PetBurst { hearts, stars, anger, sleep, note }

/// 管理面板的页签。
enum PanelTab { gallery, create, settings }

/// 一次性动作（由 `PetStage` 播放后调用 `completeAction` 复位）。
/// v2 新增：shake（拖拽甩动后抖毛）/ celebrate（吃到零食作揖）/
/// stretch（睡醒伸懒腰）/ bark（汪汪叫）。 petpack 有同名序列时播逐帧，
/// 没有时退回 MotionEngine 的程序化姿态。 
enum PetAction { none, hop, spin, drop, shake, celebrate, stretch, bark }

/// 空闲时主动发起的行为，按宠物性格加权抽取。
enum ProactiveKind { chat, treat, cuddle, zoomies }

/// 性格 -> 行为权重（纯函数，便于单元测试）。
/// 有财的 traits 是「元气 / 黏人 / 贪吃」，因此三类主动行为都会明显加权。
Map<ProactiveKind, int> proactiveWeights(List<String> traits) {
  final text = traits.join(' ');
  final weights = <ProactiveKind, int>{
    ProactiveKind.chat: 2,
    ProactiveKind.treat: 1,
    ProactiveKind.cuddle: 1,
    ProactiveKind.zoomies: 1,
  };
  if (text.contains('贪吃') || text.contains('吃货')) {
    weights[ProactiveKind.treat] = 6;
  }
  if (text.contains('黏人') || text.contains('撒娇')) {
    weights[ProactiveKind.cuddle] = 5;
  }
  if (text.contains('元气') || text.contains('活泼') || text.contains('好动')) {
    weights[ProactiveKind.zoomies] = 5;
  }
  return weights;
}

/// 用 [ticket]（0 <= ticket < 权重和）按权重区间抽取行为。
ProactiveKind proactiveKindAt(Map<ProactiveKind, int> weights, int ticket) {
  var rest = ticket;
  for (final entry in weights.entries) {
    rest -= entry.value;
    if (rest < 0) return entry.key;
  }
  return ProactiveKind.chat;
}
