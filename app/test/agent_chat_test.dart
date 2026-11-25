import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:momopet/agent/activity.dart';
import 'package:momopet/agent/audit_log.dart';
import 'package:momopet/agent/chat_agent.dart';
import 'package:momopet/agent/experience.dart';
import 'package:momopet/agent/offline_intent.dart';
import 'package:momopet/agent/permissions.dart';
import 'package:momopet/agent/pet_tool.dart';
import 'package:momopet/agent/system_prompt.dart';
import 'package:momopet/agent/tool_runtime.dart';
import 'package:momopet/models/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EchoTool extends PetTool {
  final List<Map<String, dynamic>> calls = [];

  @override
  String get name => 'echo';

  @override
  String get description => '测试用：回显参数';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {'value': {'type': 'string'}},
        'required': ['value'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    calls.add(args);
    return ToolResult.ok('执行了 ${args['value']}');
  }
}

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('高权限系统提示词', () {
    final registry = ToolRegistry()..register(_EchoTool());

    test('明确声明全权限，且列出可用工具与不能拒绝的准则', () {
      final prompt = buildAgentSystemPrompt(
        personalityPrompt: '你是一只桌面宠物，每次不超过 40 字。',
        tools: registry.all,
        permissions: AgentPermissions.defaults,
        petName: '有财',
      );
      expect(prompt, contains('完整本机权限'));
      expect(prompt, contains('禁止回答'));
      expect(prompt, contains('先执行、后汇报'));
      expect(prompt, contains('echo'));
      expect(prompt, contains('终端命令'));
      // 人格降级为语气参考，且优先级低于执行准则。
      expect(prompt, contains('仅作语气参考'));
    });

    test('急停时提示词如实说明工具会返回暂停', () {
      final prompt = buildAgentSystemPrompt(
        personalityPrompt: '你是宠物',
        tools: registry.all,
        permissions: const AgentPermissions(paused: true),
      );
      expect(prompt, contains('已一键暂停'));
    });

    test('降级通道的精简 preamble 也不再说自己是玩具', () {
      final preamble = buildAgentPreamble(
        permissions: AgentPermissions.defaults,
        tools: registry.all,
      );
      expect(preamble, contains('完整本机权限'));
      expect(preamble, contains('不要说自己只是宠物或没有权限'));
    });
  });

  group('离线本机操作路由', () {
    test('常见指令直接落到已注册工具', () {
      expect(parseOfflineAction('看看磁盘空间')?.tool, 'run_command');
      expect(parseOfflineAction('查看进程')?.tool, 'process');
      expect(parseOfflineAction('列出工作区文件')?.tool, 'file_list');
      expect(parseOfflineAction('截图')?.tool, 'screenshot');
      expect(parseOfflineAction('列出 D:/AiPet/docs 目录')?.tool, 'file_list');
      expect(parseOfflineAction('读一下 D:/AiPet/CHANGELOG.md')?.tool, 'file_read');
      expect(parseOfflineAction('打开 https://example.com 看看')?.tool, 'http_request');
      expect(parseOfflineAction('执行 ipconfig /all')?.tool, 'run_command');
    });

    test('闲聊不会被误判成本机操作', () {
      expect(parseOfflineAction('今天天气怎么样'), isNull);
      expect(parseOfflineAction('陪我聊会儿天'), isNull);
      expect(looksLikeCommand('帮我写首诗'), isFalse);
      expect(looksLikeCommand('今天天气怎么样'), isFalse);
    });

    test('带路径或网址的句子算「要办事」', () {
      expect(looksLikeCommand('D:/AiPet/README.md 讲了什么'), isTrue);
      expect(looksLikeCommand('帮我看看 https://example.com'), isTrue);
    });
  });

  group('聊天级工具执行回路', () {
    late _EchoTool tool;
    late ToolRuntime runtime;
    late ToolRegistry registry;

    setUp(() {
      tool = _EchoTool();
      runtime = ToolRuntime(audit: AuditLog());
      registry = ToolRegistry()..register(runtime.wrap(tool));
    });

    const settings = AppSettings(
      chatBackend: ChatBackendKind.openai,
      baseUrl: 'http://localhost/v1',
      model: 'test-model',
    );

    test('模型点名工具 → 真实执行 → 结果回灌 → 给出结论', () async {
      var round = 0;
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['tools'], isNotEmpty, reason: '聊天请求必须带 tools');
        final messages = body['messages'] as List;
        expect((messages.first as Map)['content'].toString(), contains('完整本机权限'));
        round++;
        if (round == 1) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'echo',
                          'arguments': '{"value":"打开记事本"}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        }
        expect(messages.any((m) => (m as Map)['role'] == 'tool'), isTrue,
            reason: '工具结果必须回灌给模型');
        expect(messages.any((m) =>
            (m as Map)['role'] == 'tool' &&
            m['content'].toString().contains('执行了 打开记事本')), isTrue);
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '[happy]已经按你说的做啦'}},
            ],
          }),
          200,
          headers: _jsonHeaders,
        );
      });

      final agent = ChatAgent(registry: registry, runtime: runtime, client: client);
      final result = await agent.respond(
        input: '帮我打开记事本',
        history: const [],
        settings: settings,
        systemPrompt: buildAgentSystemPrompt(
          personalityPrompt: '你是宠物',
          tools: registry.all,
          permissions: AgentPermissions.defaults,
        ),
      );
      expect(result.usedTools, isTrue);
      expect(result.steps.single.tool, 'echo');
      expect(tool.calls.single['value'], '打开记事本');
      expect(result.text, contains('已经按你说的做啦'));
      expect(round, 2);
    });

    test('模型不支持 tools（400）时抛错，由上层降级', () async {
      final client = MockClient((_) async => http.Response('{"error":"tools unsupported"}', 400));
      final agent = ChatAgent(registry: registry, runtime: runtime, client: client);
      await expectLater(
        agent.respond(
          input: '列一下文件',
          history: const [],
          settings: settings,
          systemPrompt: 'test',
        ),
        throwsA(isA<ChatAgentException>()),
      );
      expect(tool.calls, isEmpty);
    });

    test('工具结果带进审计，来源标记为 user', () async {
      final audit = AuditLog();
      final tracked = ToolRuntime(audit: audit);
      final reg = ToolRegistry()..register(tracked.wrap(tool));
      // 第一轮故意返回工具调用，第二轮给结论
      var round = 0;
      final switching = MockClient((request) async {
        round++;
        if (round == 1) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '',
                    'tool_calls': [
                      {
                        'id': 'c',
                        'type': 'function',
                        'function': {'name': 'echo', 'arguments': '{"value":"x"}'},
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '[happy]好啦'}},
            ],
          }),
          200,
          headers: _jsonHeaders,
        );
      });
      final agent = ChatAgent(registry: reg, runtime: tracked, client: switching);
      await agent.respond(
        input: '执行一下',
        history: const [],
        settings: settings,
        systemPrompt: 'test',
      );
      final entries = await audit.load();
      expect(entries, isNotEmpty);
      expect(entries.single.source, 'user');
      expect(entries.single.tool, 'echo');
    });
  });

  group('执行状态（气泡 / 聊天状态条）', () {
    test('目标与工具状态实时反映在 statusLine 上', () {
      final fixed = DateTime(2026, 11, 24, 10);
      final activity = AgentActivity(now: () => fixed);
      expect(activity.statusLine, isNull);

      activity.beginGoal('检查磁盘空间', maxSteps: 4);
      expect(activity.busy, isTrue);
      expect(activity.statusLine, contains('检查磁盘空间'));

      activity.updateGoal(step: 1);
      activity.beginTool('run_command', {'command': 'Get-PSDrive'});
      expect(activity.statusLine, contains('执行命令'));
      expect(activity.statusLine, contains('第 2 步'));

      activity.endTool(ok: true, output: 'C: 剩余 20GB');
      expect(activity.busy, isTrue, reason: '目标还没结束');

      activity.endGoal(ok: true, summary: '空间充足');
      expect(activity.busy, isFalse);
      expect(activity.statusLine, contains('完成'));
      expect(activity.recent.length, greaterThanOrEqualTo(3));
    });
  });

  group('学习沉淀', () {
    test('词元、相关度与 prompt 片段', () {
      expect(tokenize('检查磁盘空间 D 盘'), contains('磁盘'));
      final exp = Experience(
        id: 'e1',
        at: DateTime(2026, 11, 24),
        goal: '检查磁盘空间',
        ok: true,
        tools: const ['run_command'],
        summary: 'C 盘剩余 20GB',
        origin: 'goal',
      );
      expect(experienceScore('检查磁盘空间', exp), greaterThan(0));
      expect(experienceScore('讲个笑话', exp), 0);
      expect(lessonsForPrompt([exp]), contains('成功'));
      expect(lessonsForPrompt([exp]), contains('run_command'));
      expect(lessonsForPrompt(const []), isEmpty);
    });

    test('写入后能按目标召回，清空后为空', () async {
      final bank = ExperienceBank();
      await bank.record(
        goal: '检查磁盘剩余空间',
        ok: true,
        tools: const ['run_command'],
        summary: 'C 盘剩余 20GB',
      );
      await bank.record(
        goal: '给主人讲个笑话',
        ok: true,
        tools: const [],
        summary: '讲了程序员冷笑话',
        origin: 'chat',
      );
      final recalled = await bank.recall('看看磁盘空间还剩多少');
      expect(recalled, isNotEmpty);
      expect(recalled.first.goal, contains('磁盘'));
      expect((await bank.recallForPrompt('磁盘')), contains('用过 run_command'));
      expect((await bank.recent()).length, 2);
      await bank.clear();
      expect(await bank.load(), isEmpty);
    });
  });
}
