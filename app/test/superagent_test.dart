
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/brain_host.dart';
import 'package:momopet/agent/brainpack.dart';
import 'package:momopet/agent/offline_intent.dart';
import 'package:momopet/agent/persisted_task.dart';
import 'package:momopet/agent/speculative.dart';
import 'package:momopet/agent/task_store.dart';
import 'package:momopet/agent/triggers/app_focus_trigger.dart';
import 'package:momopet/agent/triggers/clipboard_trigger.dart';
import 'package:momopet/agent/triggers/pet_event.dart';
import 'package:momopet/agent/triggers/quiet_hours.dart';
import 'package:momopet/agent/watchdog.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 24, h, m);

class FakeClipboard implements ClipboardReader {
  FakeClipboard(this.text);
  String? text;
  @override
  Future<String?> read() async => text;
}

class FakeFocus implements FocusReader {
  FakeFocus(this.title);
  String? title;
  @override
  bool get available => true;
  @override
  Future<String?> foregroundTitle() async => title;
}

class FakeStore extends TaskStore {
  final List<PersistedTask> tasks = [];
  @override
  Future<List<PersistedTask>> load() async => List.of(tasks);
  @override
  Future<void> save(List<PersistedTask> value) async {
    tasks.clear();
    tasks.addAll(value);
  }
}

class FakeHost implements BrainHost {
  @override
  String get agentPetId => 'test-pet';
  @override
  bool get agentOnlineAvailable => true;
  @override
  AppSettings get agentSettings => const AppSettings();
  @override
  bool get agentPetMode => true;
  final List<String> bubbles = [];
  @override
  void agentBubble(String text, {PetMood mood = PetMood.talk}) => bubbles.add(text);
  @override
  void agentHop() {}
  @override
  void agentStroll({bool run = false}) {}
  @override
  void agentBeg() {}
  @override
  void agentSleep() {}
  @override
  void agentWake() {}
  @override
  void agentSpeak(String text) {}
}

void main() {
  group('M3 Trigger 模式检测', () {
    test('剪贴板只识别 URL / 英文 / 数字三类', () {
      expect(ClipboardTrigger.detectKind('https://example.com/a'), 'url');
      expect(ClipboardTrigger.detectKind('The quick brown fox jumps over the lazy dog.'), 'english');
      expect(ClipboardTrigger.detectKind('123 456 7890 1234'), 'number');
      expect(ClipboardTrigger.detectKind('今天天气不错'), isNull);
      expect(ClipboardTrigger.detectKind('   '), isNull);
    });

    test('剪贴板同一内容不重复触发，payload 不含原文', () async {
      DateTime now = at(14);
      final policy = QuietPolicy(now: () => now);
      final clipboard = FakeClipboard('https://example.com/a');
      final trigger = ClipboardTrigger(
        isEnabled: () => true,
        policy: policy,
        reader: clipboard,
        now: () => now,
      );
      final events = <PetEvent>[];
      trigger.events.listen(events.add);
      await trigger.pollOnceForTest();
      await trigger.pollOnceForTest(); // 同指纹，跳过
      expect(events.length, 1);
      expect(events.first.payload.containsKey('url'), isFalse);
      expect(events.first.summary, contains('网址'));
      trigger.dispose();
    });

    test('前台窗口分类只返回大类', () {
      expect(AppFocusTrigger.categorize('Visual Studio Code'), AppCategory.editor);
      expect(AppFocusTrigger.categorize('Google Chrome'), AppCategory.browser);
      expect(AppFocusTrigger.categorize('Microsoft Word'), AppCategory.office);
      expect(AppFocusTrigger.categorize('某个奇怪的窗口标题'), AppCategory.unknown);
    });

    test('静默时段与每日预算：显式配置旧规则仍生效', () {
      const rules = QuietHours(
        startHour: 22,
        endHour: 8,
        dailyBudget: 6,
        cooldown: Duration(seconds: 90),
      );
      final policy = QuietPolicy(rules: rules, now: () => at(23));
      expect(policy.allow('clipboard'), isFalse); // 23 点静默
      final day = QuietPolicy(rules: rules, now: () => at(14));
      expect(day.allow('a'), isTrue);
      expect(day.allow('a'), isFalse); // 冷却期内
      expect(day.allow('b'), isTrue);
    });

    test('M5 默认全天可行动、配额只防抖', () {
      expect(const QuietHours().isConfigured, isFalse);
      final policy = QuietPolicy(now: () => at(23));
      expect(policy.allow('clipboard'), isTrue);
      expect(policy.remainingBudget, greaterThan(200));
    });
  });

  group('M3 Watchdog', () {
    test('卡死任务被标记 failed', () {
      DateTime now = at(12);
      final wd = Watchdog(
        store: FakeStore(),
        host: FakeHost(),
        now: () => now,
        stuckTimeout: const Duration(minutes: 2),
      );
      final task = PersistedTask(
        id: 't1',
        kind: 'tool',
        title: '查天气',
        at: now,
        status: TaskStatus.running,
        createdAt: now.subtract(const Duration(minutes: 3)),
        startedAt: now.subtract(const Duration(minutes: 3)),
      );
      final action = wd.inspect(task, now);
      expect(action?.kind, WatchdogActionKind.stuck);
      wd.dispose();
    });

    test('重试超限与过期分别判定', () {
      final now = at(12);
      final wd = Watchdog(store: FakeStore(), host: FakeHost(), now: () => now);
      final retried = PersistedTask(
        id: 't2',
        kind: 'x',
        title: 'x',
        at: now,
        createdAt: now,
        attempts: 3,
      );
      expect(wd.inspect(retried, now)?.kind, WatchdogActionKind.retryLimit);

      final overdue = PersistedTask(
        id: 't3',
        kind: 'reminder',
        title: '老提醒',
        at: now.subtract(const Duration(hours: 2)),
        createdAt: now.subtract(const Duration(hours: 3)),
      );
      expect(wd.inspect(overdue, now)?.kind, WatchdogActionKind.expired);
      wd.dispose();
    });

    test('巡视会写回任务表并给宿主降级台词', () async {
      DateTime now = at(12);
      final store = FakeStore();
      final host = FakeHost();
      final wd = Watchdog(
        store: store,
        host: host,
        now: () => now,
        stuckTimeout: const Duration(minutes: 2),
      );
      store.tasks.add(PersistedTask(
        id: 'stuck',
        kind: 'tool',
        title: '卡住的任务',
        at: now,
        status: TaskStatus.running,
        createdAt: now.subtract(const Duration(minutes: 5)),
        startedAt: now.subtract(const Duration(minutes: 5)),
      ));
      await wd.patrolOnce();
      expect(store.tasks.single.status, TaskStatus.failed);
      expect(host.bubbles, isNotEmpty);
      wd.dispose();
    });
  });

  group('M4 brainpack', () {
    test('白名单外的条目被忽略并记警告', () {
      final pack = BrainPack.fromJson({
        'tools': {'reminder': true, 'evil_tool': true},
        'triggers': {'clipboard': true, 'keylogger': true},
      });
      expect(pack.toolEnabled('reminder'), isTrue);
      expect(pack.toolEnabled('evil_tool'), isFalse);
      expect(pack.triggerEnabled('clipboard'), isTrue);
      expect(pack.triggerEnabled('keylogger'), isFalse);
      expect(pack.warnings.length, 2);
    });

    test('M5 默认工具与感知 Trigger 全开，白名单外仍拒绝', () {
      expect(const BrainPack().triggerEnabled('clipboard'), isTrue);
      expect(const BrainPack().toolEnabled('reminder'), isTrue);
      expect(const BrainPack().toolEnabled('run_command'), isTrue);
      expect(const BrainPack().triggerEnabled('keylogger'), isFalse);
      expect(const BrainPack().toolEnabled('evil_tool'), isFalse);
      expect(BrainPack.builtInTools.length, greaterThan(10));
    });

    test('坏 JSON 回退默认且不抛异常', () {
      final pack = BrainPack.fromText('{bad json');
      expect(pack.warnings, isNotEmpty);
      expect(pack.schemaVersion, 1);
    });
  });

  group('M4 投机执行', () {
    test('显式配了静默时段就不生成草稿', () async {
      final policy = QuietPolicy(
        rules: const QuietHours(startHour: 22, endHour: 8),
        now: () => at(23),
      );
      final engine = SpeculativeEngine(
        host: FakeHost(),
        store: FakeStore(),
        policy: policy,
        now: () => at(23),
      );
      await engine.consider();
      expect(engine.drafts, isEmpty);
    });

    test('临近下班时段生成草稿并可消费', () async {
      final engine = SpeculativeEngine(
        host: FakeHost(),
        store: FakeStore(),
        now: () => at(17, 40),
        generator: (prompt) async => '主人快回来了，我等你！',
      );
      await engine.consider();
      expect(engine.drafts.length, 1);
      final draft = engine.takeDraft();
      expect(draft?.text, '主人快回来了，我等你！');
      expect(engine.drafts, isEmpty);
    });
  });

  group('M3 异步意图', () {
    test('SlowToolIntent 是 AgentIntent 的合法分支', () {
      const intent = SlowToolIntent(tool: 'weather', args: {'city': '上海'}, prompt: '我去查查天气');
      expect(intent.tool, 'weather');
      expect(intent.prompt, '我去查查天气');
    });
  });
}
