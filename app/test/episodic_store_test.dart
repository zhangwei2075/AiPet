import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/memory/episodic_event.dart';
import 'package:momopet/agent/memory/episodic_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 12, 14, 0);

  EpisodicEvent event(String id,
      {String content = '主人测试',
      int importance = 2,
      String? tag,
      EpisodeKind kind = EpisodeKind.chat,
      DateTime? at}) {
    return EpisodicEvent(
      id: id,
      petId: 'p1',
      at: at ?? now,
      kind: kind,
      content: content,
      importance: importance,
      tag: tag,
    );
  }

  group('EpisodicStore', () {
    test('写入 / 读回 / 同日同内容去重', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EpisodicStore(debounce: Duration.zero);
      store.add(event('e1', content: '主人明天要早点睡'));
      store.add(event('e2', content: '主人明天要早点睡')); // 去重
      await store.flush();
      expect(store.eventsOf('p1'), hasLength(1));

      // 新实例读回（持久化 roundtrip）
      final store2 = EpisodicStore(debounce: Duration.zero);
      await store2.load();
      expect(store2.eventsOf('p1'), hasLength(1));
      expect(store2.eventsOf('p1').first.content, '主人明天要早点睡');
    });

    test('单日上限 80 条，按重要性+最旧先淘汰', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EpisodicStore(debounce: Duration.zero);
      for (var i = 0; i < 82; i++) {
        store.add(event(
          'e$i',
          content: '事实$i',
          importance: i < 78 ? 1 : 3,
          at: now.subtract(Duration(minutes: i)),
        ));
      }
      await store.flush();
      final events = store.eventsOn('p1', dayKeyOf(now));
      expect(events.length, EpisodicStore.maxPerDay);
      // 4 条 importance=1 的最旧被淘汰，importance=3 全保留
      expect(events.where((e) => e.importance == 3).length, 4);
    });

    test('单宠物总量 400 条', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EpisodicStore(debounce: Duration.zero);
      for (var d = 0; d < 8; d++) {
        for (var i = 0; i < 60; i++) {
          store.add(event(
            'd$d-$i',
            content: '事实$d-$i',
            importance: 1,
            at: now.subtract(Duration(days: d, minutes: i)),
          ));
        }
      }
      await store.flush();
      expect(store.eventsOf('p1').length, EpisodicStore.maxPerPet);
    });

    test('digest 写入与清除，事件清除连带 digest', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EpisodicStore(debounce: Duration.zero);
      store.add(event('e1'));
      store.addDigest('p1', dayKeyOf(now.subtract(const Duration(days: 1))), '主人在忙项目');
      await store.flush();
      expect(store.hasDigest('p1', dayKeyOf(now.subtract(const Duration(days: 1)))), isTrue);

      await store.clearDay('p1', dayKeyOf(now.subtract(const Duration(days: 1))));
      expect(store.hasDigest('p1', dayKeyOf(now.subtract(const Duration(days: 1)))), isFalse);
      expect(store.eventsOf('p1'), hasLength(1)); // 今天的不受影响

      await store.clearAll('p1');
      expect(store.eventsOf('p1'), isEmpty);
    });

    test('坏数据容错：起不来不如清空', () async {
      SharedPreferences.setMockInitialValues({'aipet.episodes.v1': '{not json'});
      final store = EpisodicStore(debounce: Duration.zero);
      await store.load();
      expect(store.eventsOf('p1'), isEmpty);
    });

    test('upsertByTag：互动降噪，同 tag 当天只留一条', () async {
      SharedPreferences.setMockInitialValues({});
      final store = EpisodicStore(debounce: Duration.zero);
      store.upsertByTag(event('i1', content: '今天被摸 3 次', tag: '互动·被摸'));
      store.upsertByTag(event('i2', content: '今天被摸 8 次', tag: '互动·被摸'));
      await store.flush();
      final events = store.eventsOf('p1');
      expect(events, hasLength(1));
      expect(events.first.content, '今天被摸 8 次');
    });
  });
}
