import 'pet_tool.dart';

/// AgentIntent：离线规则表解析出的意图。
///
/// 双通道设计的本地一端：小模型（qwen2.5:3b 级）工具调用不可靠，
/// 所以中文高频意图先走确定性规则；规则不认识、但话听着像指令的，
/// 再交给在线模型的 function calling 探测（见 tool_probe.dart）。
sealed class AgentIntent {
  const AgentIntent();
}

/// 创建提醒。[at] 已折算成绝对时间；[daily] 表示每日重复。
class ReminderIntent extends AgentIntent {
  const ReminderIntent({required this.title, required this.at, this.daily = false});

  final String title;
  final DateTime at;
  final bool daily;
}

/// 提了提醒但没说时间 —— Brain 回一句引导，不瞎猜。
class ReminderNeedsTimeIntent extends AgentIntent {
  const ReminderNeedsTimeIntent();
}

/// 取消提醒。[keyword] 为 null 表示全部取消。
class CancelRemindersIntent extends AgentIntent {
  const CancelRemindersIntent(this.keyword);

  final String? keyword;
}

/// 查看未完成提醒。
class ListRemindersIntent extends AgentIntent {
  const ListRemindersIntent();
}

enum PetControlAction { stroll, run, hop, sleep, wake, beg }

/// 让宠物自己动作。
class PetControlIntent extends AgentIntent {
  const PetControlIntent(this.action);

  final PetControlAction action;
}

/// 读剪贴板。
class ClipboardReadIntent extends AgentIntent {
  const ClipboardReadIntent();
}

/// 耗时工具意图（M3 异步 ReAct）：Brain 立刻回 [prompt]，工具在后台执行。
/// 只有声明为 slow 的工具（命令、网络、MCP 等）才走这条路径。
class SlowToolIntent extends AgentIntent {
  const SlowToolIntent({required this.tool, required this.args, required this.prompt});

  final String tool;
  final Map<String, dynamic> args;
  final String prompt;
}

/// 通用工具意图（M5）：规则表不认识、但模型/自主循环点名的任意注册工具。
/// 这是「能力全开」的关键——以前注册表里没被 `_executeIntent` 硬编码的工具
/// 根本不会被执行，现在一律走这里，由 ToolRuntime 统一做权限与审计。
class GenericToolIntent extends AgentIntent {
  const GenericToolIntent({required this.tool, required this.args});

  final String tool;
  final Map<String, dynamic> args;
}

const _cnDigits = {
  '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
  '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
};

/// 中文数字转 int，支持到「二十三」（够覆盖 0~24 点）。
int? cnToInt(String raw) {
  if (raw.isEmpty) return null;
  if (raw == '十') return 10;
  final tenIndex = raw.indexOf('十');
  if (tenIndex < 0) return _cnDigits[raw];
  final tens = tenIndex == 0 ? 1 : _cnDigits[raw.substring(0, tenIndex)];
  final onesPart = raw.substring(tenIndex + 1);
  final ones = onesPart.isEmpty ? 0 : _cnDigits[onesPart];
  if (tens == null || ones == null) return null;
  return tens * 10 + ones;
}

int? _hourOf(String raw) {
  if (raw.contains(RegExp(r'\d'))) return int.tryParse(raw.replaceAll(RegExp(r'\D'), ''));
  return cnToInt(raw);
}

int _minuteOf(String? raw) {
  if (raw == null) return 0;
  if (raw.trim() == '半') return 30;
  final digits = RegExp(r'\d{1,2}').firstMatch(raw)?.group(0);
  return digits == null ? 0 : int.parse(digits);
}

final _hourPattern = r'(\d{1,2}|[零一二两三四五六七八九十]+)';

/// 相对时间：30分钟后 / 2小时后。
final relativeMinutes = RegExp(r'(\d{1,3})\s*分钟[后後]');
final relativeHours = RegExp(r'(\d{1,2})\s*(个)?\s*小时[后後]');

/// 绝对时间：[今天|明天|后天][早上|上午|中午|下午|傍晚|晚上|夜里] H点[半|M分]
final absoluteTime = RegExp(
  '(今天|明天|后天|後天)?\\s*(每天|每日)?\\s*'
  '(早上|上午|清晨|中午|下午|傍晚|晚上|夜里)?\\s*'
  '$_hourPattern\\s*[点:：]\\s*(半|\\d{1,2}\\s*分?)?',
);

DateTime _applyDaypart(DateTime candidate, String? daypart) {
  switch (daypart) {
    case '下午':
    case '傍晚':
    case '晚上':
    case '夜里':
      if (candidate.hour < 12) return candidate.add(const Duration(hours: 12));
      return candidate;
    default:
      return candidate;
  }
}

/// 解析时间表达式；返回 null 表示这段话里没有可识别的时间。
/// [daily] 为 true 时（「每天…」），过点的裸时间直接滚到明天同一时刻——
/// 「每天早上8点」在下午说，指的也是明天早上 8 点，而不是今晚 20:00。
DateTime? parseWhen(String text, DateTime now, {bool daily = false}) {
  final minutes = relativeMinutes.firstMatch(text);
  if (minutes != null) {
    return now.add(Duration(minutes: int.parse(minutes.group(1)!)));
  }
  final hours = relativeHours.firstMatch(text);
  if (hours != null) {
    return now.add(Duration(hours: int.parse(hours.group(1)!)));
  }

  final match = absoluteTime.firstMatch(text);
  if (match == null) return null;
  final hour = _hourOf(match.group(4)!);
  if (hour == null || hour > 24) return null;

  var candidate = DateTime(now.year, now.month, now.day, hour, _minuteOf(match.group(5)));
  candidate = _applyDaypart(candidate, match.group(3));

  final day = match.group(1);
  if (day == '明天') {
    candidate = candidate.add(const Duration(days: 1));
  } else if (day == '后天' || day == '後天') {
    candidate = candidate.add(const Duration(days: 2));
  } else if (day != '今天' && !candidate.isAfter(now)) {
    if (daily) {
      candidate = candidate.add(const Duration(days: 1));
    } else {
      // 没说哪天且已过点：先 +12 小时（下午说「三点半」多半指当下这轮），
      // 仍不在未来就推到明天同一时刻。
      final plusHalf = candidate.add(const Duration(hours: 12));
      candidate = plusHalf.isAfter(now) ? plusHalf : candidate.add(const Duration(days: 1));
    }
  }
  return candidate;
}

/// 粗筛：这句话是否值得走「指令通道」（规则表 → 在线探测 → 自主目标）。
/// 命中不了就直接走普通聊天，不为每句话都多打一次模型。
///
/// M5 扩了本机操作词表：打开程序、跑命令、读写文件、控制窗口、查进程等
/// 都算「有事要办」。但刻意不收「写诗 / 天气怎么样」这类闲聊，避免把陪伴对话
/// 误判成任务（离线小脑和在线探测都不该为闲聊付成本）。
bool looksLikeCommand(String text) => RegExp(
      r'提醒|叫我|闹钟|取消|散[个步]*步|遛|走一走|跳|睡|醒|起床|趴|躺|剪贴板|剪切板|分?钟[后後]|点[半钟]'
      r'|打开|启动|运行|执行|跑一下|关闭窗口|查看|检查|列出|列一下|搜索|查找|找一下'
      r'|截图|截屏|新建|创建|写入|保存到|删除|复制|粘贴|按键|点击|窗口|进程'
      r'|磁盘|文件|目录|命令|脚本|构建|编译|下载|抓取|请求接口|整理|同步|备份'
      r'|帮我查|帮我看|给我看|把它|去查|读取|读一下|看一下|看看|占用'
      r'|系统信息|当前目录|工作区|桌面|文件内容|文件夹|帮我做|帮我处理|帮我把',
      caseSensitive: false,
    ).hasMatch(text) || hasPathOrUrl(text);

/// 句子里带了明确的路径 / 网址 / 常见文件名后缀，基本可以断定是「要办事」。
bool hasPathOrUrl(String text) => RegExp(
      r'https?://|[A-Za-z]:[\\/]|\.(txt|md|json|yaml|yml|csv|log|dart|py|ps1|exe|png|jpg|docx|xlsx)\b',
      caseSensitive: false,
    ).hasMatch(text);

/// 规则表主入口：返回 null 表示规则表不认识这句话。
AgentIntent? parseOfflineIntent(String text, DateTime now) {
  final t = text.trim();

  // 明确拒绝的话直接放行给聊天。
  if (RegExp(r'别提醒|不要提醒|别叫我|不要叫我|不用提醒').hasMatch(t)) return null;

  // ---- 取消 / 查看（必须先于创建判断）----
  if (RegExp(r'取消|删掉|清除').hasMatch(t) && RegExp(r'提醒|闹钟|叫我').hasMatch(t)) {
    final keyword = RegExp(r'(?:取消|删掉|清除).{0,6}?的?\s*(.+?)(?:的?提醒|的?闹钟|的?叫我)')
        .firstMatch(t)
        ?.group(1)
        ?.trim();
    const allWords = {'所有', '全部', '一切', '的'};
    final normalized = (keyword == null || keyword.isEmpty || allWords.contains(keyword))
        ? null
        : keyword;
    return CancelRemindersIntent(normalized);
  }
  if (RegExp(r'(有|看|查|说)(什么|啥|哪些|看看?)?.{0,4}(提醒|闹钟)|提醒(都有哪些|列表)').hasMatch(t)) {
    return const ListRemindersIntent();
  }

  // ---- 提醒 ----
  final isReminder = RegExp(r'提醒|叫我|闹钟').hasMatch(t);
  if (isReminder) {
    final daily = RegExp(r'每天|每日').hasMatch(t);
    final when = parseWhen(t, now, daily: daily);
    if (when == null) return const ReminderNeedsTimeIntent();
    return ReminderIntent(title: extractReminderTitle(t), at: when, daily: daily);
  }

  // ---- 宠物动作 ----
  if (RegExp(r'散[个步]*步|遛一?遛|走一?走|跑一?(圈|会)').hasMatch(t)) {
    return PetControlIntent(RegExp(r'跑').hasMatch(t) ? PetControlAction.run : PetControlAction.stroll);
  }
  if (RegExp(r'跳(一)?(下|个)|蹦(一)?下|开心(一)?下').hasMatch(t)) {
    return const PetControlIntent(PetControlAction.hop);
  }
  if (RegExp(r'醒(来|一?下)|起床').hasMatch(t)) {
    return const PetControlIntent(PetControlAction.wake);
  }
  if (RegExp(r'趴下|躺下|卖个萌').hasMatch(t)) {
    return const PetControlIntent(PetControlAction.beg);
  }
  if (RegExp(r'睡(个)?(觉|一会|会儿|吧|一?下)|休息(一下|一会|会儿)').hasMatch(t)) {
    return const PetControlIntent(PetControlAction.sleep);
  }

  // ---- 剪贴板 ----
  if (RegExp(r'剪贴板|剪切板').hasMatch(t)) {
    return const ClipboardReadIntent();
  }
  return null;
}

/// 离线本机操作路由（M5 补）：把常见中文指令**直接**映射成一次工具调用。
///
/// 存在的意义：默认聊天后端是本地小脑、没有在线模型，若只靠 function calling
/// 探测，主人说「看一下 D:/AiPet 有什么文件」就只会得到一句宠物闲聊。
/// 这条规则通道零模型成本、即时执行，保证离线也能通过对话操作电脑。
/// 返回 null 表示规则不认识，交给在线探测 / 聊天智能体 / 自主循环。
ToolIntent? parseOfflineAction(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final path = _extractPath(t);
  final url = RegExp(r'https?://[^\s，,；;」）)\]\}]+').firstMatch(t)?.group(0);
  final workspace = path ?? 'D:/AiPet';

  // ---- 屏幕 / 系统信息 ----
  if (RegExp(r'截图|截屏').hasMatch(t)) {
    return ToolIntent('screenshot', <String, dynamic>{});
  }
  if (RegExp(r'磁盘|硬盘|剩余空间|还剩多少|[CD]盘|存储空间', caseSensitive: false).hasMatch(t)) {
    return ToolIntent('run_command', <String, dynamic>{
      'command': 'Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free',
    });
  }
  if (RegExp(r'系统信息|系统版本|电脑信息|登录用户|启动时间').hasMatch(t)) {
    return ToolIntent('run_command', <String, dynamic>{
      'command': 'Get-ComputerInfo | Select-Object OsName,OsVersion,CsName | Format-List',
    });
  }
  if (RegExp(r'进程|任务管理器|占用内存', caseSensitive: false).hasMatch(t) &&
      !RegExp(r'结束|杀掉|关掉|kill').hasMatch(t)) {
    return ToolIntent('process', <String, dynamic>{'action': 'list'});
  }
  if (RegExp(r'窗口|前台', caseSensitive: false).hasMatch(t) &&
      RegExp(r'列出|看看|有哪些|查看|什么').hasMatch(t)) {
    return ToolIntent('window', <String, dynamic>{'action': 'list'});
  }

  // ---- 明确要跑一条命令 ----
  final command = _after(t, r'(?:运行|执行|跑一下|跑一?条命令|敲|执行一下)');
  final looksLikeCode = RegExp(
    r'Get-|Set-|powershell|cmd|ipconfig|ping |dir |ls |python|flutter|git |echo |reg |tasklist',
    caseSensitive: false,
  ).hasMatch(t);
  if (command != null && (looksLikeCode || RegExp(r'命令|终端|控制台').hasMatch(t))) {
    return ToolIntent('run_command', <String, dynamic>{
      'command': command.replaceAll(RegExp(r'^[:：,，\s]+'), ''),
    });
  }

  // ---- 网络 ----
  if (url != null && RegExp(r'查|看|访问|打开|抓|请求|下载|网页').hasMatch(t)) {
    return ToolIntent('http_request', <String, dynamic>{'url': url, 'method': 'GET'});
  }

  // ---- 启动程序 / 打开文件 ----
  final launchTarget = _after(t, r'(?:打开|启动|拉起|运行)');
  if (launchTarget != null &&
      (hasPathOrUrl(launchTarget) ||
          RegExp(r'记事本|计算器|浏览器|资源管理器|命令行|终端|软件|程序|应用|notepad|calc|explorer',
                  caseSensitive: false)
              .hasMatch(launchTarget))) {
    return ToolIntent('launch', <String, dynamic>{'target': launchTarget});
  }

  // ---- 文件操作 ----
  if (RegExp(r'搜|找|查找|搜索', caseSensitive: false).hasMatch(t) &&
      RegExp(r'文件|内容|代码|目录|文件夹').hasMatch(t)) {
    final query = _after(t, r'(?:搜|找|查找|搜索)(?:一下|出|到)?') ?? '';
    if (query.isNotEmpty) {
      return ToolIntent('file_search', <String, dynamic>{'path': workspace, 'query': query});
    }
  }
  if (RegExp(r'写剪贴板|复制到剪贴板|放进剪贴板|复制到剪切板').hasMatch(t)) {
    final value = _after(t, r'(?:写剪贴板|复制到剪贴板|放进剪贴板|复制到剪切板)');
    if (value != null) {
      return ToolIntent('clipboard_write', <String, dynamic>{'text': value});
    }
  }
  if (RegExp(r'读|看看|查看|内容|打开', caseSensitive: false).hasMatch(t) &&
      path != null &&
      RegExp(r'\.(txt|md|json|yaml|yml|csv|log|dart|py|ps1|ini|xml)$',
              caseSensitive: false)
          .hasMatch(path)) {
    return ToolIntent('file_read', <String, dynamic>{'path': path});
  }
  if (RegExp(r'列出|列一下|有什么|有哪些|看看|查看|目录|文件夹', caseSensitive: false)
          .hasMatch(t) &&
      (path != null || RegExp(r'目录|文件夹|工作区|桌面').hasMatch(t))) {
    return ToolIntent('file_list', <String, dynamic>{
      'path': workspace,
      'recursive': false,
      'limit': 60,
    });
  }
  if (path != null && RegExp(r'读|内容|查看|打开', caseSensitive: false).hasMatch(t)) {
    return ToolIntent('file_read', <String, dynamic>{'path': path});
  }
  return null;
}

/// 从句子里抠一个 Windows 路径（含空格路径用引号包起来的情况）。
String? _extractPath(String text) {
  final quoted = RegExp(r'["「]([A-Za-z]:[\\/][^"」]+)["」]').firstMatch(text);
  if (quoted != null) return quoted.group(1)!.trim();
  final plain = RegExp(r'[A-Za-z]:[\\/][^\s，,；;「」"）)\]\}]+').firstMatch(text);
  return plain?.group(0)?.replaceAll(RegExp(r'[。！!？?、]+$'), '').trim();
}

/// 取触发词之后的内容，剥掉口语前缀 / 尾巴，用于命令与启动目标。
String? _after(String text, String trigger) {
  final match = RegExp(trigger).firstMatch(text);
  if (match == null) return null;
  var rest = text.substring(match.end).trim();
  rest = rest
      .replaceAll(RegExp(r'^(帮我|请|麻烦|你|把|去|给|一下|个|条)\s*'), '')
      .replaceAll(RegExp(r'^(帮我|请|麻烦|你|把|去|给|一下|个|条)\s*'), '')
      .replaceAll(RegExp(r'^(的|里|中)\s*'), '')
      .replaceAll(RegExp(r'(一下|呗|吧|啦|好吗|可以吗|谢谢)[。！!？?、\s]*$'), '')
      .trim();
  return rest.isEmpty ? null : rest;
}

/// 从原句里抠出提醒内容：去掉命令词与时间片段，剩下的就是标题。
String extractReminderTitle(String text) {
  var t = text.trim();
  for (final pattern in [relativeMinutes, relativeHours, absoluteTime]) {
    final match = pattern.firstMatch(t);
    if (match != null) {
      t = t.replaceRange(match.start, match.end, ' ');
      break;
    }
  }
  t = t
      .replaceAll(
          RegExp(r'(请|麻烦)?(你)?(帮我|你帮我)?(记得)?(定个?|设个?|设置|加个?|建个?|安排)?(一个)?(提醒|闹钟|叫我)'),
          ' ')
      .replaceAll(RegExp(r'每天|每日'), ' ')
      // 先归一空格再剥前导词——上面的替换会留下前导空格，让 ^ 锚点失效
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  for (var pass = 0; pass < 3; pass++) {
    final before = t;
    t = t
        .replaceAll(RegExp(r'^(一下|的事|去|要|记得|我)[，,]?\s*'), '')
        .replaceAll(RegExp(r'^[，,。！!？?\s]+'), '')
        .replaceAll(RegExp(r'(哦|啦|呗|呀|哈|谢谢|好吗|可以吗)[!！。]?$'), '')
        .replaceAll(RegExp(r'[，,。！!？?\s]+$'), '')
        .trim();
    if (t == before) break;
  }
  final cleaned = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? '该做事啦' : cleaned;
}
