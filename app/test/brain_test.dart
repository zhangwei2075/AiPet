import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/brain.dart';
import 'package:momopet/agent/brain_host.dart';
import 'package:momopet/agent/persisted_task.dart';
import 'package:momopet/agent/task_store.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假宿主：记录 Brain 对外的一切动作，供断言。
class FakeHost implements BrainHost {
  FakeHost({this.online = false});

  bool online;
  final List<String> bubbles = [];
  final List<String> spoken = [];
  int hops = 0;
  int strolls = 0;
  int sleeps = 0;
  int wakes = 0;
  int begs = 0;

  @override
  String get agentPetId => 'p1';

  @override
  bool get agentOnlineAvailable => online;

  @override
  AppSettings get agentSettings => const AppSettings();

  @override
  bool get agentPetMode => true;

  @override
  void agentBubble(String text, {PetMood mood = PetMood.talk}) => bubbles.add(text);

  @override
  void agentHop() => hops++;

  @override
  void agentStroll({bool run = false}) => strolls++;

  @override
  void agentBeg() => begs++;

  @override
  void agentSleep() => sleeps++;

  @override
  void agentWake() => wakes++;

  @override
  void agentSpeak(String text) => spoken.add(text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHost host;
  late TaskStore store;
  late PetBrain brain;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 12, 14, 0);
    host = FakeHost();
    store = TaskStore();
    brain = PetBrain(host: host, store: store, now: () => now);
  });

  tearDown(() => brain.dispose());

  group('handleUserText 意图执行', () {
    test('「提醒我15:30喝水」→ 建任务 + 确认回复', () async {
      final reply = await brain.handleUserText('提醒我15:30喝水');
      expect(reply, isNotNull);
      expect(reply!.text, contains('15:30'));
      expect(reply.text, contains('喝水'));

      final tasks = await store.load();
      expect(tasks, hasLength(1));
      expect(tasks.first.title, '喝水');
      expect(tasks.first.at, DateTime(2026, 11, 12, 15, 30));
      expect(tasks.first.isScheduled, isTrue);
    });

    test('「陪我散个步」→ 触发散步 + 俏皮回复', () async {
      final reply = await brain.handleUserText('陪我散个步吧');
      expect(reply, isNotNull);
      expect(host.strolls, 1);
    });

    test('「跳一下」→ 开心跳', () async {
      await brain.handleUserText('跳一下');
      expect(host.hops, 1);
    });

    test('普通聊天 → 返回 null 交给聊天流', () async {
      expect(await brain.handleUserText('今天天气怎么样'), isNull);
      expect(host.strolls, 0);
    });
  });

  group('到期巡视（TimerTrigger 等价逻辑）', () {
    test('到点提醒 → 气泡 + 跳一下 + 任务完成', () async {
      final tasks = [
        PersistedTask(
          id: 'r1',
          kind: 'reminder',
          title: '喝水',
          at: now.add(const Duration(seconds: 5)),
          createdAt: now,
        ),
      ];
      await store.save(tasks);
      await brain.start();

      now = now.add(const Duration(seconds: 30)); // 心跳周期 20s，此刻已到期
      await brain.handleTickForTest();

      expect(host.bubbles.single, contains('喝水'));
      expect(host.hops, 1);
      final saved = await store.load();
      expect(saved.first.status, TaskStatus.done);
    });

    test('每日提醒触发后顺延一天', () async {
      await store.save([
        PersistedTask(
          id: 'd1',
          kind: 'reminder',
          title: '跑步',
          at: DateTime(2026, 11, 12, 14, 5),
          repeat: TaskRepeat.daily,
          createdAt: now,
        ),
      ]);
      await brain.start();
      now = now.add(const Duration(minutes: 10));
      await brain.handleTickForTest();

      final saved = await store.load();
      expect(saved.first.isScheduled, isTrue);
      expect(saved.first.at, DateTime(2026, 11, 13, 14, 5));
    });

    test('启动补报：错过 30 分钟内的提醒补一次，更早的标记过期', () async {
      await store.save([
        PersistedTask(
          id: 'm1',
          kind: 'reminder',
          title: '刚错过的',
          at: now.subtract(const Duration(minutes: 10)),
          createdAt: now,
        ),
        PersistedTask(
          id: 'm2',
          kind: 'reminder',
          title: '早就过了的',
          at: now.subtract(const Duration(hours: 3)),
          createdAt: now,
        ),
      ]);
      await brain.start();

      expect(host.bubbles.single, contains('刚错过的'));
      final saved = await store.load();
      expect(saved.firstWhere((t) => t.id == 'm1').status, TaskStatus.done);
      expect(saved.firstWhere((t) => t.id == 'm2').status, TaskStatus.expired);
    });
  });

  group('取消与查看', () {
    test('取消全部', () async {
      await store.save([
        PersistedTask(
          id: 'c1',
          kind: 'reminder',
          title: '喝水',
          at: now.add(const Duration(hours: 1)),
          createdAt: now,
        ),
      ]);
      final reply = await brain.handleUserText('取消所有提醒');
      expect(reply!.text, contains('清掉'));
      expect((await store.load()).first.status, TaskStatus.cancelled);
    });

    test('查看列表', () async {
      await store.save([
        PersistedTask(
          id: 'l1',
          kind: 'reminder',
          title: '喝水',
          at: now.add(const Duration(hours: 1)),
          createdAt: now,
        ),
      ]);
      final reply = await brain.handleUserText('我有什么提醒吗');
      expect(reply!.text, contains('喝水'));
    });

    test('没有提醒时取消 → 温和提示而非报错', () async {
      final reply = await brain.handleUserText('取消所有提醒');
      expect(reply!.text, contains('没有找到'));
    });
  });
}
