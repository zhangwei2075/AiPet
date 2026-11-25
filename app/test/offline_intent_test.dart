import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/offline_intent.dart';

void main() {
  // 固定「现在」：2026-11-12 14:00 周四，时间解析的断言都基于它。
  final now = DateTime(2026, 11, 12, 14, 0);

  group('parseWhen 时间解析', () {
    test('HH:MM 绝对时间', () {
      expect(parseWhen('提醒我15:30喝水', now), DateTime(2026, 11, 12, 15, 30));
    });

    test('三点半 + 中文数字：14:00 说的是下午那轮（+12h）', () {
      expect(parseWhen('三点半叫我开会', now), DateTime(2026, 11, 12, 15, 30));
    });

    test('下午X点自动 +12h', () {
      expect(parseWhen('下午4点提醒我取快递', now), DateTime(2026, 11, 12, 16, 0));
    });

    test('没有说哪天且已过点 → +12h 兜底', () {
      // 现在 14:00，说「9点」→ 今晚 21:00（+12h）
      expect(parseWhen('提醒我9点吃饭', now), DateTime(2026, 11, 12, 21, 0));
    });

    test('每日任务过点的裸时间滚到明天（不做 +12h）', () {
      expect(parseWhen('每天早上8点跑步', now, daily: true), DateTime(2026, 11, 13, 8, 0));
    });

    test('X分钟后', () {
      expect(parseWhen('30分钟后叫我起来', now), now.add(const Duration(minutes: 30)));
    });

    test('明天X点', () {
      expect(parseWhen('明天早上8点叫我起床', now), DateTime(2026, 11, 13, 8, 0));
    });

    test('没有时间返回 null', () {
      expect(parseWhen('提醒我多喝水', now), isNull);
    });
  });

  group('parseOfflineIntent 意图分类', () {
    test('「提醒我15:30喝水」→ 一次性提醒，标题是喝水', () {
      final intent = parseOfflineIntent('提醒我15:30喝水', now);
      expect(intent, isA<ReminderIntent>());
      final reminder = intent! as ReminderIntent;
      expect(reminder.daily, isFalse);
      expect(reminder.at, DateTime(2026, 11, 12, 15, 30));
      expect(reminder.title, '喝水');
    });

    test('「每天早上8点跑步」→ 每日提醒', () {
      final intent = parseOfflineIntent('每天早上8点提醒我跑步', now)! as ReminderIntent;
      expect(intent.daily, isTrue);
      expect(intent.at.hour, 8);
      expect(intent.title, '跑步');
    });

    test('「取消所有提醒」→ 全部取消', () {
      expect(parseOfflineIntent('取消所有提醒', now), isA<CancelRemindersIntent>());
    });

    test('「我有什么提醒」→ 查看', () {
      expect(parseOfflineIntent('我有什么提醒吗', now), isA<ListRemindersIntent>());
    });

    test('「别提醒我喝水」→ 明确拒绝，不建任务', () {
      expect(parseOfflineIntent('别提醒我喝水', now), isNull);
    });

    test('「提醒我多喝水」→ 缺时间，走引导', () {
      expect(parseOfflineIntent('提醒我多喝水', now), isA<ReminderNeedsTimeIntent>());
    });

    test('「陪我散个步」→ 散步', () {
      final intent = parseOfflineIntent('陪我散个步吧', now)! as PetControlIntent;
      expect(intent.action, PetControlAction.stroll);
    });

    test('「跑一圈」→ 小跑', () {
      final intent = parseOfflineIntent('跑一圈给我看', now)! as PetControlIntent;
      expect(intent.action, PetControlAction.run);
    });

    test('「跳一下」「起床啦」「趴下」', () {
      expect(
        (parseOfflineIntent('跳一下', now)! as PetControlIntent).action,
        PetControlAction.hop,
      );
      expect(
        (parseOfflineIntent('起床啦', now)! as PetControlIntent).action,
        PetControlAction.wake,
      );
      expect(
        (parseOfflineIntent('趴下', now)! as PetControlIntent).action,
        PetControlAction.beg,
      );
    });

    test('「剪贴板里有什么」→ 读剪贴板', () {
      expect(parseOfflineIntent('剪贴板里有什么', now), isA<ClipboardReadIntent>());
    });

    test('普通聊天不误判', () {
      expect(parseOfflineIntent('今天天气怎么样', now), isNull);
      expect(parseOfflineIntent('你喜欢什么音乐', now), isNull);
    });
  });

  group('extractReminderTitle 标题提取', () {
    test('命令在前时间在中', () {
      expect(extractReminderTitle('提醒我15:30喝水'), '喝水');
    });

    test('命令在前带修饰词', () {
      expect(extractReminderTitle('帮我定个提醒，明天8点叫我起床'), '起床');
    });

    test('剥完只剩语气词 → 默认标题', () {
      expect(extractReminderTitle('提醒我一下'), '该做事啦');
    });
  });

  test('looksLikeCommand 粗筛', () {
    expect(looksLikeCommand('提醒我15:30喝水'), isTrue);
    expect(looksLikeCommand('我想睡觉'), isTrue);
    expect(looksLikeCommand('帮我写首诗'), isFalse);
    expect(looksLikeCommand('今天天气怎么样'), isFalse);
  });
}
