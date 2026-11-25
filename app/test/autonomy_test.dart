import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/audit_log.dart';
import 'package:momopet/agent/autonomy.dart';
import 'package:momopet/agent/brain_host.dart';
import 'package:momopet/agent/permissions.dart';
import 'package:momopet/agent/pet_tool.dart';
import 'package:momopet/agent/tool_probe.dart';
import 'package:momopet/agent/tool_runtime.dart';
import 'package:momopet/agent/tools/desktop_tools.dart';
import 'package:momopet/agent/tools/file_tools.dart';
import 'package:momopet/agent/tools/system_tools.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHost implements BrainHost {
  final List<String> bubbles = [];
  final List<String> spoken = [];

  @override
  String get agentPetId => 'p1';
  @override
  bool get agentOnlineAvailable => false;
  @override
  AppSettings get agentSettings => const AppSettings();
  @override
  bool get agentPetMode => true;
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
  void agentSpeak(String text) => spoken.add(text);
}

class _FakeRunner implements CommandRunner {
  final List<String> calls = [];

  @override
  Future<ShellResult> run(
    String command, {
    String? cwd,
    required int timeoutSeconds,
    String shell = 'auto',
  }) async {
    calls.add(command);
    return const ShellResult(exitCode: 0, stdout: 'C: 100GB free', stderr: '');
  }
}

class _EchoTool extends PetTool {
  const _EchoTool(this.cap);

  final AgentCapability? cap;

  @override
  String get name => 'echo';
  @override
  String get description => '回声工具';
  @override
  Map<String, dynamic> get parametersSchema => {'type': 'object', 'properties': {}};
  @override
  AgentCapability? get capability => cap;
  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async =>
      ToolResult.ok('echo: ${args['text'] ?? ''}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AuditLog audit;
  late ToolRuntime runtime;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    audit = AuditLog(prefs: prefs);
    runtime = ToolRuntime(audit: audit);
  });

  group('M5 权限模型', () {
    test('默认全部能力已授予，急停与否决生效', () {
      const permissions = AgentPermissions.defaults;
      expect(permissions.isFullAccess, isTrue);
      expect(permissions.allows(AgentCapability.command), isTrue);
      expect(permissions.copyWith(paused: true).allows(AgentCapability.command), isFalse);
      final narrowed = permissions.withCapability(AgentCapability.input, false);
      expect(narrowed.isFullAccess, isFalse);
      expect(narrowed.allows(AgentCapability.input), isFalse);
      expect(narrowed.allows(AgentCapability.command), isTrue);
      expect(permissions.withAll(false).enabled, isEmpty);
    });

    test('不可逆命令默认拦截，关掉开关即完全放行', () {
      const permissions = AgentPermissions.defaults;
      expect(permissions.blockedReason('format C:'), isNotNull);
      expect(permissions.blockedReason('rm -rf /'), isNotNull);
      expect(permissions.blockedReason('Get-ChildItem D:\\AiPet'), isNull);
      expect(
        permissions.copyWith(blockIrreversible: false).blockedReason('format C:'),
        isNull,
      );
      expect(
        permissions.copyWith(blockedPatterns: const []).blockedReason('format C:'),
        isNull,
      );
    });

    test('JSON 往返；旧配置缺 enabled 时回落全开', () {
      const original = AgentPermissions(
        enabled: {AgentCapability.command, AgentCapability.fileWrite},
        paused: true,
        blockIrreversible: false,
        maxStepsPerGoal: 7,
      );
      final restored = AgentPermissions.fromJson(original.toJson());
      expect(restored.enabled, original.enabled);
      expect(restored.paused, isTrue);
      expect(restored.blockIrreversible, isFalse);
      expect(restored.maxStepsPerGoal, 7);
      expect(AgentPermissions.fromJson({}).isFullAccess, isTrue);
    });

    test('设置与 AppSettings 默认开启自主与感知', () {
      expect(const AppSettings().autonomyEnabled, isTrue);
      expect(const AppSettings().perceptionEnabled, isTrue);
      expect(AppSettings.fromJson(const AppSettings().toJson()).autonomyEnabled, isTrue);
    });
  });

  group('M5 ToolRuntime', () {
    test('包装后元数据不变，执行写审计且脱敏', () async {
      final wrapped = runtime.wrap(const _EchoTool(null));
      expect(wrapped.name, 'echo');
      expect(wrapped.parametersSchema['type'], 'object');
      final result = await wrapped.invoke({'text': 'hi', 'apiKey': 'sk-secret'});
      expect(result.success, isTrue);
      final entries = await audit.load();
      expect(entries, hasLength(1));
      expect(entries.single.tool, 'echo');
      expect(entries.single.ok, isTrue);
      expect(entries.single.argsSummary, contains('***'));
      expect(entries.single.argsSummary, isNot(contains('sk-secret')));
    });

    test('能力未授予 / 急停 / 策略拦截都不执行工具', () async {
      final guarded = runtime.wrap(const _EchoTool(AgentCapability.input));
      expect((await guarded.invoke({})).success, isTrue);
      runtime.applyPermissions(
        AgentPermissions.defaults.withCapability(AgentCapability.input, false),
      );
      expect((await guarded.invoke({})).message, contains('未授予'));
      runtime.applyPermissions(AgentPermissions.defaults.copyWith(paused: true));
      expect((await guarded.invoke({})).message, contains('已暂停'));
    });

    test('命令黑名单经 validate 拦截且留下失败审计', () async {
      final runner = _FakeRunner();
      final tool = runtime.wrap(RunCommandTool(runner: runner));
      final result = await tool.invoke({'command': 'format C:'});
      expect(result.success, isFalse);
      expect(runner.calls, isEmpty);
      expect((await audit.load()).single.ok, isFalse);
    });
  });

  group('M5 本机工具', () {
    test('命令拼装与输出格式', () {
      expect(SystemCommandRunner.buildInvocation('echo hi', 'powershell').first,
          'powershell.exe');
      expect(SystemCommandRunner.buildInvocation('echo hi', 'cmd').sublist(0, 2),
          ['cmd.exe', '/c']);
      expect(
        formatShellResult(const ShellResult(
          exitCode: 0,
          stdout: 'ok',
          stderr: '',
          timedOut: false,
        )),
        contains('STDOUT:'),
      );
    });

    test('RunCommandTool 走注入的 runner 并返回输出', () async {
      final runner = _FakeRunner();
      final result = await RunCommandTool(runner: runner).invoke({'command': 'Get-PSDrive'});
      expect(result.success, isTrue);
      expect(result.message, contains('100GB free'));
      expect(runner.calls.single, 'Get-PSDrive');
    });

    test('路径与通配、键码、工具清单', () {
      expect(resolvePath('  D:/a.txt '), 'D:/a.txt');
      expect(globToRegExp('*.log').hasMatch('app.log'), isTrue);
      expect(globToRegExp('*.log').hasMatch('app.txt'), isFalse);
      expect(virtualKeyOf('ctrl'), 0x11);
      expect(virtualKeyOf('A'), 0x41);
      expect(virtualKeyOf('不认识'), isNull);
      expect(buildSystemTools(), hasLength(4));
      expect(buildFileTools(), hasLength(6));
      expect(buildDesktopTools(), hasLength(3));
    });

    test('删除工具拒绝目录，HTTP 工具拒绝非法 URL', () {
      const del = FileDeleteTool();
      expect(
        del.validate({'path': Directory.systemTemp.path}, AgentPermissions.defaults),
        contains('目录'),
      );
      final httpTool = HttpRequestTool();
      expect(httpTool.validate({'url': 'not a url'}, AgentPermissions.defaults), isNotNull);
      expect(httpTool.validate({'url': 'https://example.com'}, AgentPermissions.defaults), isNull);
    });
  });

  group('M5 自主循环', () {
    test('离线规划按关键字选只读工具', () {
      expect(offlinePlan('检查磁盘空间', ''), isA<PlanToolCall>());
      expect((offlinePlan('检查磁盘空间', '') as PlanToolCall).tool, 'run_command');
      expect((offlinePlan('看看进程', '') as PlanToolCall).tool, 'process');
      expect(offlinePlan('随便聊聊', ''), isA<PlanFail>());
      expect(offlinePlan('检查磁盘空间', '1. 已执行'), isA<PlanFinish>());
    });

    test('目标 JSON 往返与状态判定', () {
      final goal = Goal(
        id: 'g1',
        title: '整理清单',
        origin: 'self',
        status: GoalStatus.running,
        createdAt: DateTime(2026, 11, 24, 10),
        updatedAt: DateTime(2026, 11, 24, 10),
        steps: [
          GoalStep(
            tool: 'run_command',
            argsSummary: '{"command":"dir"}',
            ok: true,
            output: 'ok',
            at: DateTime(2026, 11, 24, 10),
          ),
        ],
        maxSteps: 5,
      );
      final restored = Goal.fromJson(goal.toJson());
      expect(restored.status, GoalStatus.running);
      expect(restored.steps.single.tool, 'run_command');
      expect(restored.active, isTrue);
      expect(restored.copyWith(status: GoalStatus.done).active, isFalse);
    });

    test('离线目标两步完成并留下审计（来源 goal）', () async {
      final runner = _FakeRunner();
      final registry = ToolRegistry()
        ..register(runtime.wrap(RunCommandTool(runner: runner)));
      final store = GoalStore(prefs: prefs);
      final now = DateTime(2026, 11, 24, 10);
      final host = _FakeHost();
      final loop = AutonomyLoop(
        host: host,
        registry: registry,
        runtime: runtime,
        store: store,
        probe: ToolProbe(),
        isEnabled: () => true,
        settings: () => const AppSettings(),
        onlineAvailable: () => false,
        permissions: () => AgentPermissions.defaults
            .copyWith(selfDriveIntervalMinutes: 0),
        now: () => now,
      );
      await store.save([
        Goal(
          id: 'g1',
          title: '检查磁盘空间',
          origin: 'user',
          status: GoalStatus.queued,
          createdAt: now,
          updatedAt: now,
          maxSteps: 4,
        ),
      ]);

      await loop.tick();
      var goals = await store.load();
      expect(goals.single.status, GoalStatus.running);
      expect(goals.single.steps.single.tool, 'run_command');
      expect(runner.calls, hasLength(1));

      await loop.tick(); // history 非空 → offlinePlan 收尾
      goals = await store.load();
      expect(goals.single.status, GoalStatus.done);
      expect(host.bubbles, isNotEmpty);
      expect((await audit.load()).any((e) => e.source == 'goal'), isTrue);
      loop.dispose();
    });

    test('急停 / 关闭自主后 tick 不动；步数上限触发熔断', () async {
      final store = GoalStore(prefs: prefs);
      final now = DateTime(2026, 11, 24, 10);
      var enabled = false;
      final loop = AutonomyLoop(
        host: _FakeHost(),
        registry: ToolRegistry(),
        runtime: runtime,
        store: store,
        probe: ToolProbe(),
        isEnabled: () => enabled,
        settings: () => const AppSettings(),
        onlineAvailable: () => false,
        permissions: () => AgentPermissions.defaults
            .copyWith(selfDriveIntervalMinutes: 0),
        now: () => now,
      );
      await store.save([
        Goal(
          id: 'g2',
          title: '超步数',
          origin: 'user',
          status: GoalStatus.queued,
          createdAt: now,
          updatedAt: now,
          maxSteps: 1,
          steps: [
            GoalStep(
              tool: 'echo',
              argsSummary: '{}',
              ok: true,
              output: 'ok',
              at: now,
            ),
          ],
        ),
      ]);
      await loop.tick(); // 关闭状态，应无变化
      expect((await store.load()).single.status, GoalStatus.queued);
      enabled = true;
      await loop.tick();
      expect((await store.load()).single.status, GoalStatus.failed);
      loop.dispose();
    });
  });
}
