import 'package:flutter/foundation.dart';

/// 规则抽取出的一条事实（归一化后的第三人称短句）。
@immutable
class ExtractedFact {
  const ExtractedFact(this.content, this.importance, [this.tag]);

  final String content;
  final int importance;
  final String? tag;
}

/// 聊天事实的规则抽取器（docs/m2-memory-plan.md §4）。
///
/// 双通道里「本地保底」的一端：不依赖模型，离线也能工作；
/// 在线时的 LLM 精抽只是增强，失败静默回退到这里。
/// · 先按句切分、过敏感过滤；
/// · 命中句式的转成第三人称短句（我→主人），并给出重要性与话题标签；
/// · 每句话最多抽 2 条，疑问句/寒暄跳过。
class FactExtractor {
  const FactExtractor();

  /// 敏感信息模式：手机号 / 身份证 / 银行卡长号 / 密码类字样。
  static final _sensitive = RegExp(
    r'(1[3-9]\d{9})|(\d{17}[\dXx])|(\d{16,19})|(密码|口令|验证码|账号.*\d{6,})',
  );

  static final _sentenceSplit = RegExp(r'[。！！？；;\n]+');

  /// 否定疑问/寒暄直接跳过。
  static final _skipSuffix = RegExp(r'(吗|呢|吧|么)$');

  /// 计划/约定（含时间词）→ importance 3。
  static final _plan = RegExp(
    r'^(我|咱|人家)?(明天|后天|後天|下周|下星期|下个月|大?[一二三四五六七八九十]+号|\d{1,2}号)'
    r'|(要|打算|准备|得|计划|约了?|订了?|买了?)(去|回|见|见个?面|出差|旅游|搬家|考试|面试)',
  );

  /// 偏好 → importance 2。
  static final _preference = RegExp(r'^(我|咱)?(最)?(喜欢|爱吃|爱喝|爱看|讨厌|不喜欢|受不了|迷上)');

  /// 一般自述/意向 → importance 2。
  static final _intention = RegExp(r'^(我|咱)?(想|要|得|准备|打算|决定)');

  /// 自我信息 → importance 2。
  static final _identity = RegExp(r'^(我|咱)(叫|是|在|住|家在|来自)');

  /// 话题标签表：首个命中的词面作为 tag，检索加分 + 当日合并去重。
  static final _topics = <String, RegExp>{
    '吃': RegExp(r'吃|饭|菜|辣|甜|火锅|外卖|零食'),
    '睡': RegExp(r'睡|觉|午休|熬夜|失眠'),
    '工作': RegExp(r'工作|上班|加班|开会|项目|老板|需求'),
    '出行': RegExp(r'上海|北京|出差|旅游|飞机|高铁|火车|搬家'),
    '运动': RegExp(r'跑步|健身|游泳|球|瑜伽|锻炼'),
    '娱乐': RegExp(r'电影|剧|歌|游戏|动漫|小说'),
    '宠物': RegExp(r'猫|狗|仓鼠|鸟|鱼|宠物'),
    '提醒': RegExp(r'提醒|闹钟|会议|约定|截止'),
    '健康': RegExp(r'感冒|发烧|头疼|牙疼|医院|药|体检'),
  };

  /// 供 LLM 抽取结果复检：命中敏感模式的一律不落盘。
  static bool isSensitive(String text) => _sensitive.hasMatch(text);

  /// 从一句用户输入里抽取 0~2 条事实。
  List<ExtractedFact> extract(String userText, DateTime now) {
    final results = <ExtractedFact>[];
    for (final raw in userText.split(_sentenceSplit)) {
      if (results.length >= 2) break;
      final sentence = raw.trim();
      if (sentence.length < 4 || sentence.length > 60) continue;
      if (_sensitive.hasMatch(sentence)) continue;
      if (_skipSuffix.hasMatch(sentence)) continue;

      ExtractedFact? fact;
      if (_plan.hasMatch(sentence)) {
        fact = ExtractedFact(_normalize(sentence), 3, _tagOf(sentence));
      } else if (_preference.hasMatch(sentence)) {
        fact = ExtractedFact(_normalize(sentence), 2, _tagOf(sentence));
      } else if (_identity.hasMatch(sentence)) {
        fact = ExtractedFact(_normalize(sentence), 2, _tagOf(sentence));
      } else if (_intention.hasMatch(sentence)) {
        fact = ExtractedFact(_normalize(sentence), 2, _tagOf(sentence));
      }
      if (fact != null && !results.any((e) => e.content == fact!.content)) {
        results.add(fact);
      }
    }
    return results;
  }

  /// 「我明天要早点睡」→「主人明天要早点睡」。
  String _normalize(String sentence) {
    var t = sentence
        .replaceAll(RegExp(r'[嗯嗯呃噢哦喔哈嘿欸诶，,]'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    t = t.replaceFirst(RegExp(r'^(咱|人家)'), '我');
    if (t.startsWith('我')) {
      t = '主人${t.substring(1)}';
    } else if (!t.startsWith('主人')) {
      t = '主人$t';
    }
    return t.length > 40 ? t.substring(0, 40) : t;
  }

  String? _tagOf(String sentence) {
    for (final entry in _topics.entries) {
      if (entry.value.hasMatch(sentence)) return entry.key;
    }
    return null;
  }
}
