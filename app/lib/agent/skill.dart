import 'package:flutter/foundation.dart';

/// 技能 = 可组合的提示词模板，与「工具」的区别：
/// · Tool 有副作用（设提醒、读剪贴板），走 function calling；
/// · Skill 只扩展模型能力（翻译/总结/解释），注入 system prompt 的一段指令。
///
/// 这样弱模型也能「会用技能」——不需要 function calling，只在提示词里
/// 告诉它遇到某类输入该按什么格式回答。本地小脑也能照着模板做简化版。
@immutable
class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.prompt,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;

  /// 注入 system prompt 的指令片段。
  final String prompt;

  final bool enabled;

  Skill copyWith({bool? enabled}) => Skill(
        id: id,
        name: name,
        description: description,
        prompt: prompt,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {'id': id, 'enabled': enabled};

  @override
  String toString() => 'Skill($name: $description)';
}

/// 技能注册表：内置清单 + 用户开关（开关持久化在 SkillStore）。
class SkillRegistry {
  SkillRegistry([List<Skill>? skills]) {
    if (skills != null) {
      for (final skill in skills) {
        _skills[skill.id] = skill;
      }
    }
  }

  final Map<String, Skill> _skills = {};

  void register(Skill skill) => _skills[skill.id] = skill;

  Skill? lookup(String id) => _skills[id];

  List<Skill> get all => _skills.values.toList(growable: false);

  List<Skill> get enabled => all.where((s) => s.enabled).toList(growable: false);

  void setEnabled(String id, bool value) {
    final skill = _skills[id];
    if (skill != null) _skills[id] = skill.copyWith(enabled: value);
  }

  void applySwitches(Map<String, bool> switches) {
    switches.forEach((id, value) {
      if (_skills.containsKey(id)) setEnabled(id, value);
    });
  }

  /// 按用户这句话选用技能：只有明确触发才注入，避免每条消息都塞满提示词。
  String buildPromptFragmentFor(String userText) {
    final matched = enabled.where((s) => _matches(s.id, userText)).toList(growable: false);
    if (matched.isEmpty) return '';
    return matched.map((s) => s.prompt).join('\n');
  }

  static bool _matches(String skillId, String text) => switch (skillId) {
        'translate' => text.contains('翻译') || text.contains('译成') || text.contains('translate'),
        'summary' => text.contains('总结') || text.contains('概括') || text.contains('简短说'),
        'explain' => text.contains('解释') || text.contains('什么是') || text.contains('为什么'),
        'continue' => text.contains('续写') || text.contains('接着写'),
        _ => false,
      };
}

/// 内置技能：4 个高频文本能力，全部是提示词，零副作用。
final List<Skill> builtInSkills = [
  const Skill(
    id: 'translate',
    name: '翻译',
    description: '把用户给的外文译成中文，或反过来',
    prompt: '用户要求翻译时，只给译文，不解释；保持原文的语气与分段。',
  ),
  const Skill(
    id: 'summary',
    name: '总结',
    description: '把长文本压成几句要点',
    prompt: '用户要求总结时，用不超过 3 条短句概括，先给结论。',
  ),
  const Skill(
    id: 'explain',
    name: '解释',
    description: '用简单的话解释复杂概念',
    prompt: '用户要求解释时，用日常比喻和短句，避免术语堆砌。',
  ),
  const Skill(
    id: 'continue',
    name: '续写',
    description: '接着用户给的段落往下写',
    prompt: '用户要求续写时，保持原文的文风与视角，直接接着写，不复述前文。',
  ),
];
