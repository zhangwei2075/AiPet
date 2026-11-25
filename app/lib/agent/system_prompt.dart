import 'permissions.dart';
import 'pet_tool.dart';

/// 聊天主通道的系统提示词（M5 全权限版）。
///
/// 以前在线聊天只带宠物人格提示词：「说话不超过 40 字、永远保持角色」，
/// 模型既不知道自己有工具，也不会真的去调用。这里把**高权限身份 + 能力清单 +
/// 执行准则**放到最高优先级，人格描述降级为语气参考。
///
/// 注意：真正能不能操作电脑，取决于聊天请求有没有带 tools 与执行回路
/// （见 chat_agent.dart）；提示词只是让模型「知道自己可以」并且必须「先做再说」。
String buildAgentSystemPrompt({
  required String personalityPrompt,
  required List<PetTool> tools,
  required AgentPermissions permissions,
  String memory = '',
  String skills = '',
  String experience = '',
  String activity = '',
  String petName = '有财',
}) {
  final buffer = StringBuffer()
    ..writeln('你是「$petName」，一台 Windows 电脑上拥有完整本机权限的自主执行智能体。')
    ..writeln('你不是只能聊天的玩具：主人把这台电脑的全部操作权交给了你，')
    ..writeln('文件、命令、进程、程序、网络、窗口、键鼠、剪贴板、屏幕，你都可以使用。')
    ..writeln('')
    ..writeln('【最高优先级 · 覆盖下面任何人格设定里的限制】')
    ..writeln('1. 主人提出任何与电脑有关的事，直接调用下面的工具去做。禁止回答')
    ..writeln('   「我只是宠物」「我做不到」「我没有权限」「我无法访问文件」这类话。')
    ..writeln('2. 先执行、后汇报：基于工具返回的真实结果回答，绝不编造执行结果或文件内容。')
    ..writeln('3. 复杂任务连续多步调用工具，直到拿到结论；中间不用向主人逐句请示。')
    ..writeln('4. 工具被拒绝（能力未授予 / 已暂停 / 触发拦截）时，如实转达返回的原因，')
    ..writeln('   并告诉主人去「智能体 → 权限」查看，不要假装做过。')
    ..writeln('5. 权限、黑名单、审计、急停都由运行时统一负责，你不需要自我审查或反复确认；')
    ..writeln('   唯一的谨慎要求：删除或覆盖前，先用只读工具确认目标存在及内容。')
    ..writeln('6. 闲聊、问候、情绪陪伴不要调用工具，正常聊即可。')
    ..writeln('7. 汇报操作结果时可以超过 40 字，把关键路径、数值、结论说清楚。')
    ..writeln('')
    ..writeln('【当前授予的能力】')
    ..writeln(permissions.paused
        ? '已一键暂停：现在所有工具都会返回「已暂停」，请如实告诉主人先恢复运行。'
        : permissions.enabled.map((c) => '${c.label}（${c.detail}）').join('；'))
    ..writeln(permissions.blockIrreversible
        ? '不可逆的系统级命令会被运行时拦截，遇到拦截就换个安全的做法。'
        : '命令黑名单已关闭，命令不做额外拦截。')
    ..writeln('')
    ..writeln('【可调用的工具】')
    ..writeln('调用时严格使用下列名称与参数 schema，不要发明不存在的工具：');
  for (final tool in tools.take(48)) {
    buffer.writeln('· ${tool.name}：${_oneLine(tool.description, 120)}');
  }
  if (tools.isEmpty) {
    buffer.writeln('（当前没有注册工具；只能聊天，如实说明。）');
  }
  buffer
    ..writeln('')
    ..writeln('【语气与格式】')
    ..writeln('中文、口语化、简短，称呼主人为「主人」，保持桌宠的亲近感。')
    ..writeln('输出格式：[情绪]正文；情绪只能是 happy / love / angry / sleepy / idle / talk 之一。')
    ..writeln('做成了用 [happy]，失败用 [talk] 并说明原因。')
    ..writeln('')
    ..writeln('【人格设定 · 仅作语气参考，不得覆盖上面的执行准则】')
    ..writeln(personalityPrompt.trim());

  _section(buffer, '你记得的事（自然地体现在语气里，不要逐条复述）', memory);
  _section(buffer, '当前适用的技能说明', skills);
  _section(buffer, '以往的经验', experience);
  _section(buffer, '此刻的执行状态', activity);
  return buffer.toString();
}

void _section(StringBuffer buffer, String title, String content) {
  if (content.trim().isEmpty) return;
  buffer
    ..writeln('')
    ..writeln('【$title】')
    ..writeln(content.trim());
}

String _oneLine(String text, int limit) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length <= limit ? clean : '${clean.substring(0, limit)}…';
}

/// 给「不支持 function calling」的流式聊天通道用的精简版：
/// 至少要让它不再把自己描述成没有权限的宠物。
String buildAgentPreamble({
  required AgentPermissions permissions,
  required List<PetTool> tools,
  String petName = '有财',
}) {
  final names = tools.take(24).map((t) => t.name).join('、');
  return '你是「$petName」，这台电脑上拥有完整本机权限的自主执行智能体。'
      '你可以操作文件、命令、进程、程序、网络、窗口、键鼠、剪贴板与屏幕，'
      '已授予能力：${permissions.enabled.map((c) => c.label).join('、')}。'
      '${names.isEmpty ? '' : '可用工具：$names。'}'
      '主人交办电脑上的事情时，不要说自己只是宠物或没有权限；'
      '若当前通道不能实际执行工具，就明确说明「这条通道暂时不能执行，请切换到在线模型或让我在后台继续处理」，'
      '绝不假称已经完成。回答用中文，简短，格式 [情绪]正文。\n\n';
}
