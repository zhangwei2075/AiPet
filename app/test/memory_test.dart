import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/data/memory_store.dart';
import 'package:momopet/models/pet_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PetGrowth', () {
    test('按互动点分阶段', () {
      expect(PetGrowth.forPoints(0), PetGrowth.stranger);
      expect(PetGrowth.forPoints(9), PetGrowth.stranger);
      expect(PetGrowth.forPoints(10), PetGrowth.familiar);
      expect(PetGrowth.forPoints(29), PetGrowth.familiar);
      expect(PetGrowth.forPoints(30), PetGrowth.attached);
      expect(PetGrowth.forPoints(70), PetGrowth.inseparable);
      expect(PetGrowth.forPoints(9999), PetGrowth.inseparable);
    });

    test('进度与剩余量', () {
      const points = 20;
      final stage = PetGrowth.forPoints(points);
      expect(stage, PetGrowth.familiar);
      expect(stage.progressOf(points), closeTo(0.5, 0.001));
      expect(stage.remainingToNext(points), 10);
      expect(PetGrowth.inseparable.remainingToNext(100), 0);
    });
  });

  group('PetMemory', () {
    test('互动点数 = 摸头 + 聊天×2', () {
      final memory = PetMemory(petId: 'p', firstMet: DateTime.now(), lastSeen: DateTime.now(), taps: 5, chats: 3);
      expect(memory.points, 11);
      expect(memory.growth, PetGrowth.familiar);
    });

    test('没有互动时提示词片段为空', () {
      final memory = PetMemory(petId: 'p', firstMet: DateTime.now(), lastSeen: DateTime.now());
      expect(memory.promptSummary, isEmpty);
      expect(memory.shortLine, contains('认识'));
    });

    test('提示词片段带上天数、次数与话题', () {
      final memory = PetMemory(
        petId: 'p',
        firstMet: DateTime.now().subtract(const Duration(days: 4)),
        lastSeen: DateTime.now(),
        taps: 12,
        chats: 2,
        topics: {'加班': 3, '周末': 1},
        notes: ['第一次和主人说话'],
      );

      final summary = memory.promptSummary;
      expect(summary, contains('5 天'));
      expect(summary, contains('12 次'));
      expect(summary, contains('加班'));
      expect(summary, contains('第一次和主人说话'));
      expect(memory.daysTogether, 5);
    });

    test('JSON 往返', () {
      final memory = PetMemory(
        petId: 'p1',
        firstMet: DateTime(2026, 1, 2),
        lastSeen: DateTime(2026, 1, 8),
        taps: 7,
        chats: 4,
        topics: {'工作': 2},
        notes: ['第一次聊天'],
      );
      final back = PetMemory.fromJson(memory.toJson(), petId: 'p1');
      expect(back.taps, 7);
      expect(back.chats, 4);
      expect(back.topics['工作'], 2);
      expect(back.notes, ['第一次聊天']);
      expect(back.firstMet, DateTime(2026, 1, 2));
    });
  });

  group('MemoryStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('摸头会被持久化，重开也还在', () async {
      final store = MemoryStore();
      await store.load();
      await store.tap('doudou');
      await store.tap('doudou', amount: 2);

      expect(store.of('doudou').taps, 3);

      final reopened = MemoryStore();
      await reopened.load();
      expect(reopened.of('doudou').taps, 3);
    });

    test('第 20 次摸头会留下里程碑', () async {
      final store = MemoryStore();
      await store.load();
      String? milestone;
      for (var i = 0; i < 20; i++) {
        milestone = await store.tap('doudou');
      }
      expect(milestone, contains('20'));
      expect(store.of('doudou').notes, contains(contains('20')));
    });

    test('聊天记轮次并提取话题', () async {
      final store = MemoryStore();
      await store.load();
      await store.chat('doudou', '今天加班好累啊');
      await store.chat('doudou', '周末一起去玩吧');

      final memory = store.of('doudou');
      expect(memory.chats, 2);
      expect(memory.topics.keys, containsAll(['工作', '情绪', '周末']));
      expect(memory.notes, contains('第一次和主人说话'));
    });

    test('清空记忆只影响这一只', () async {
      final store = MemoryStore();
      await store.load();
      await store.tap('a');
      await store.tap('b');
      await store.clear('a');

      expect(store.of('a').taps, 0);
      expect(store.of('b').taps, 1);
    });

    test('话题数量与备注数量有上限', () async {
      final store = MemoryStore();
      await store.load();
      for (var i = 0; i < 14; i++) {
        await store.note('p', '里程碑 $i');
      }
      await store.chat('p', '工作 学习 吃饭 睡觉 难过 游戏 天气 周末');

      expect(store.of('p').notes.length, lessThanOrEqualTo(12));
      expect(store.of('p').topics.length, lessThanOrEqualTo(8));
    });
  });
}
