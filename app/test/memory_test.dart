import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/memory/episodic_event.dart';
import 'package:momopet/agent/memory/episodic_store.dart';
import 'package:momopet/agent/memory/extractor.dart';
import 'package:momopet/agent/memory/memory_service.dart';
import 'package:momopet/agent/memory/retrieval.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 12, 22, 30);

  group('FactExtractor 规则抽取', () {
    const extractor = FactExtractor();

    test('计划句 → importance 3', () {
      final facts = extractor.extract('我明天要早点睡', now);
      expect(facts, hasLength(1));
      expect(facts.first.importance, 3);
      expect(facts.first.content, '主人明天要早点睡');
      expect(facts.first.tag, '睡');
    });

    test('偏好句 → importance 2 + 话题标签', () {
      final facts = extractor.extract('我最喜欢吃辣', now);
      expect(facts.first.importance, 2);
      expect(facts.first.tag, '吃');
      expect(facts.first.content, '主人最喜欢吃辣');
    });

    test('出行计划带地名标签', () {
      final facts = extractor.extract('我下周要去上海出差', now);
      expect(facts, isNotEmpty);
      expect(facts.first.tag, '出行');
    });

    test('敏感信息不落盘', () {
      expect(extractor.extract('我手机号是13812345678记一下', now), isEmpty);
      expect(extractor.extract('我的密码是123456', now), isEmpty);
      expect(FactExtractor.isSensitive('密码是abc123'), isTrue);
    });

    test('疑问句跳过', () {
      expect(extractor.extract('我喜欢吃辣吗', now), isEmpty);
    });

    test('寒暄不抽', () {
      expect(extractor.extract('你好呀 哈哈 在吗', now), isEmpty);
    });

    test('单句最多 2 条', () {
      final facts = extractor.extract('我喜欢吃辣。我讨厌香菜。我想养猫。我想去看海', now);
      expect(facts.length, 2);
    });
  });

  group('EpisodeRetrieval 检索', () {
    const retrieval = EpisodeRetrieval();

    EpisodicEvent event(String content,
        {int importance = 2, DateTime? at, EpisodeKind kind = EpisodeKind.chat}) {
      return EpisodicEvent(
        id: content,
        petId: 'p1',
        at: at ?? now.subtract(const Duration(hours: 1)),
        kind: kind,
        content: content,
        importance: importance,
      );
    }

    test('词面命中排前', () {
      final events = [
        event('主人明天要早点睡'),
        event('主人喜欢吃辣', at: now.subtract(const Duration(days: 10))),
      ];
      final hits = retrieval.retrieve(events: events, query: '今晚早点睡觉', now: now);
      expect(hits.first.event.content, '主人明天要早点睡');
    });

    test('时间衰减：新事件 > 同重要性的旧事件', () {
      final events = [
        event('主人喜欢看电影', at: now.subtract(const Duration(days: 20))),
        event('主人喜欢听歌', at: now.subtract(const Duration(hours: 2))),
      ];
      final hits = retrieval.retrieve(events: events, query: '', now: now);
      expect(hits.first.event.content, '主人喜欢听歌');
    });

    test('topK 与 600 字符预算', () {
      final events = [
        for (var i = 0; i < 30; i++)
          event('主人说了一件事${'很' * 30}', at: now.subtract(Duration(minutes: i))),
      ];
      final hits = retrieval.withinBudget(
          retrieval.retrieve(events: events, query: '', now: now));
      expect(hits.length, lessThan(30));
      var used = 0;
      for (final hit in hits) {
        used += hit.event.content.length + 2;
      }
      expect(used, lessThanOrEqualTo(600));
    });
  });

  group('MemoryService 组装与管道', () {
    late EpisodicStore store;
    late MemoryService service;
    late DateTime now;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 11, 12, 22, 0);
      store = EpisodicStore(debounce: Duration.zero);
      service = MemoryService(store: store, now: () => now);
      await service.load();
    });

    test('assemble：计数记忆 + digest + topK 三层拼接', () async {
      store.add(EpisodicEvent(
        id: 'e1',
        petId: 'p1',
        at: now.subtract(const Duration(days: 1)),
        kind: EpisodeKind.chat,
        content: '主人说明天要早点睡',
        importance: 3,
      ));
      store.addDigest('p1', dayKeyOf(now.subtract(const Duration(days: 1))), '主人聊了睡觉的事');
      await store.flush();

      final text = service.assemble(
        petId: 'p1',
        query: '今晚早点睡吗',
        countMemory: '被摸 10 次；聊过 3 次。',
      );
      expect(text, contains('被摸 10 次'));
      expect(text, contains('最近的日子'));
      expect(text, contains('主人说明天要早点睡'));
    });

    test('assemble：没有任何情景时退化为纯计数记忆（老用户兼容）', () {
      final text = service.assemble(petId: 'p1', query: '你好', countMemory: '被摸 3 次');
      expect(text, '被摸 3 次');
    });

    test('assemble：2000 字符硬预算', () async {
      for (var i = 0; i < 50; i++) {
        store.add(EpisodicEvent(
          id: 'e$i',
          petId: 'p1',
          at: now.subtract(Duration(hours: i)),
          kind: EpisodeKind.chat,
          content: '长事实' * 80,
          importance: 3,
        ));
      }
      await store.flush();
      final text = service.assemble(petId: 'p1', query: '', countMemory: '');
      expect(text.length, lessThanOrEqualTo(2000));
    });

    test('recordFromChat：规则命中入库；敏感与寒暄不入库', () async {
      await service.recordFromChat(petId: 'p1', userText: '我明天要去上海出差');
      await service.recordFromChat(petId: 'p1', userText: '我手机号是13812345678');
      await service.recordFromChat(petId: 'p1', userText: '哈哈哈');
      final events = store.eventsOf('p1');
      expect(events, hasLength(1));
      expect(events.first.content, contains('上海'));
    });

    test('recordTask / recordInteraction 管道', () async {
      service.recordTask('p1', '主人设了一个提醒：喝水');
      service.recordInteraction('p1', '被摸', amount: 5);
      service.recordInteraction('p1', '被摸', amount: 3);
      final events = store.eventsOf('p1');
      expect(events, hasLength(2));
      expect(events.firstWhere((e) => e.kind == EpisodeKind.interaction).content,
          '今天被摸8 次');
    });

    test('extractionEnabled 关闭后不记新东西', () async {
      await service.setExtractionEnabled(false);
      await service.recordFromChat(petId: 'p1', userText: '我明天要早点睡');
      service.recordTask('p1', '主人设了一个提醒');
      expect(store.eventsOf('p1'), isEmpty);
    });

    test('dailyRollIfNeeded：给有事件且无摘要的日子生成模板摘要', () async {
      final yesterday = now.subtract(const Duration(days: 1));
      store.add(EpisodicEvent(
        id: 'e1',
        petId: 'p1',
        at: yesterday,
        kind: EpisodeKind.chat,
        content: '主人说明天要早点睡',
        importance: 3,
      ));
      await store.flush();

      await service.dailyRollIfNeeded('p1'); // 离线（settings=null）走模板

      final digest = store.digestsOf('p1')[dayKeyOf(yesterday)];
      expect(digest, isNotNull);
      expect(digest, contains('早点睡'));

      // 幂等：再跑一次不重复生成
      await service.dailyRollIfNeeded('p1');
      expect(store.digestsOf('p1').length, 1);
    });

    test('viewDays：按天倒序', () async {
      store.add(EpisodicEvent(
        id: 'a',
        petId: 'p1',
        at: now.subtract(const Duration(days: 2)),
        kind: EpisodeKind.chat,
        content: '前天的事',
        importance: 1,
      ));
      store.add(EpisodicEvent(
        id: 'b',
        petId: 'p1',
        at: now,
        kind: EpisodeKind.chat,
        content: '今天的事',
        importance: 1,
      ));
      await store.flush();
      final days = service.viewDays('p1');
      expect(days.first.day, dayKeyOf(now));
      expect(days.last.day, dayKeyOf(now.subtract(const Duration(days: 2))));
    });
  });
}
