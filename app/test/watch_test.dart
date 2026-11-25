import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/brain_host.dart';
import 'package:momopet/agent/tools/watch_tools.dart';
import 'package:momopet/agent/watch.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/models/settings.dart';
import 'package:momopet/state/app_controller.dart';
import 'package:momopet/ui/settings_tab.dart';
import 'package:momopet/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHost implements BrainHost {
  final List<String> bubbles = [];
  final List<String> spoken = [];

  @override
  String get agentPetId => 'p1';
  @override
  bool get agentOnlineAvailable => true;
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

class _FakeFetcher extends WatchFetcher {
  _FakeFetcher(this.items);

  List<WatchItem> items;
  int calls = 0;
  Object? error;

  @override
  Future<List<WatchItem>> fetch(WatchSourceKind kind, {int count = 30}) async {
    calls++;
    if (error != null) throw error!;
    return items;
  }
}

WatchItem _item(String id, String title,
        {String summary = '', List<String> tags = const []}) =>
    WatchItem(
      id: id,
      title: title,
      summary: summary,
      url: 'https://www.cls.cn/detail/$id',
      at: DateTime(2026, 11, 25, 18),
      tags: tags,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('财联社接口', () {
    test('签名是 md5(sha1(排序后的 query))，URI 带齐参数与 sign', () {
      final params = CailiansheApi.params(count: 5);
      final sign = CailiansheApi.sign(params);
      expect(sign, hasLength(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(sign), isTrue);

      final uri = CailiansheApi.uri(count: 5);
      expect(uri.host, 'www.cls.cn');
      expect(uri.path, '/v1/roll/get_roll_list');
      expect(uri.queryParameters['app'], 'CailianpressWeb');
      expect(uri.queryParameters['rn'], '5');
      expect(uri.queryParameters['sign'], sign);
      // 参数顺序固定（排序后），换顺序签名就会变 —— 服务端按原文校验。
      expect(uri.query.startsWith('app=CailianpressWeb&category='), isTrue);
    });

    test('解析 roll_data：标题 / 摘要 / 标签 / 时间', () {
      const body = '''
{"errno":0,"msg":"","data":{"roll_data":[
  {"id":2544352,"ctime":1795602085,
   "title":"高盛：数据中心建设热潮有望持续至2028年",
   "brief":"【高盛：数据中心建设热潮有望持续至2028年】财联社11月25日电，受人工智能热潮推动…",
   "shareurl":"https://api3.cls.cn/share/article/2544352",
   "subjects":[{"subject_name":"人工智能"}]},
  {"id":2544353,"ctime":1795602027,"title":"","brief":"【行云科技：首次回购公司股份】财联社11月25日电…","subjects":[]}
]}}''';
      final items = CailiansheApi.parse(body);
      expect(items, hasLength(2));
      expect(items.first.id, '2544352');
      expect(items.first.tags, ['人工智能']);
      expect(items.first.at.year, 2026);
      // 没 title 的条目从 brief 的【】里补
      expect(items[1].title, '行云科技：首次回购公司股份');
    });

    test('errno 非 0 时报出服务端原因，不静默返回空列表', () {
      expect(
        () => CailiansheApi.parse('{"errno":"10012","msg":"签名错误"}'),
        throwsA(isA<WatchException>()),
      );
    });
  });

  group('订阅调度', () {
    test('开通即抓一次：只推命中的，历史全部记为已见', () async {
      final store = WatchStore(prefs: prefs);
      final host = _FakeHost();
      final fetcher = _FakeFetcher([
        _item('1', '光模块龙头宣布扩产', tags: ['光通信']),
        _item('2', '某公司回购股份'),
        _item('3', '光通信招标落地'),
      ]);
      final service = WatchService(
        store: store,
        host: host,
        fetcher: fetcher,
        now: () => DateTime(2026, 11, 25, 18),
      );

      final watch = await service.create(
        name: '财联社·光模块',
        keywords: ['光模块', '光通信'],
        intervalMinutes: 30,
      );
      final result = await service.runNow(watch.id);

      expect(result!.fetched, 3);
      expect(result.hits, 2);
      expect(result.notified, isTrue);
      expect(host.bubbles, hasLength(1));
      expect(host.bubbles.first, contains('光模块龙头'));

      final stored = (await store.load()).single;
      expect(stored.seenIds, containsAll(['1', '2', '3']));
      expect(stored.lastRunAt, isNotNull);
      expect(stored.pushCount, 1);
    });

    test('第二次抓同样的条目不再推送；新增的才推', () async {
      final store = WatchStore(prefs: prefs);
      final host = _FakeHost();
      final fetcher = _FakeFetcher([_item('1', '光模块扩产')]);
      var now = DateTime(2026, 11, 25, 18);
      final service = WatchService(
        store: store,
        host: host,
        fetcher: fetcher,
        now: () => now,
      );
      final watch = await service.create(name: '光模块', keywords: ['光模块']);
      await service.runNow(watch.id);
      final afterFirst = host.bubbles.length;

      now = now.add(const Duration(minutes: 31));
      await service.pump(); // 同一条内容，不重复推
      expect(host.bubbles.length, afterFirst);

      fetcher.items = [_item('2', '光模块新一轮涨价'), ...fetcher.items];
      now = now.add(const Duration(minutes: 31));
      await service.pump();
      expect(host.bubbles.length, afterFirst + 1);
      expect(host.bubbles.last, contains('新一轮涨价'));
    });

    test('没到间隔不抓，到了才抓', () async {
      final store = WatchStore(prefs: prefs);
      final fetcher = _FakeFetcher([_item('1', '光模块扩产')]);
      var now = DateTime(2026, 11, 25, 18);
      final service = WatchService(
        store: store,
        host: _FakeHost(),
        fetcher: fetcher,
        now: () => now,
      );
      final watch = await service.create(
          name: '光模块', keywords: ['光模块'], intervalMinutes: 30);
      await service.runNow(watch.id);
      final calls = fetcher.calls;

      now = now.add(const Duration(minutes: 10));
      await service.pump();
      expect(fetcher.calls, calls);

      now = now.add(const Duration(minutes: 25));
      await service.pump();
      expect(fetcher.calls, calls + 1);
    });

    test('暂停的订阅不抓', () async {
      final store = WatchStore(prefs: prefs);
      final fetcher = _FakeFetcher([_item('1', '光模块扩产')]);
      final service = WatchService(
        store: store,
        host: _FakeHost(),
        fetcher: fetcher,
        now: () => DateTime(2026, 11, 25, 18),
      );
      final watch = await service.create(name: '光模块', keywords: ['光模块']);
      await service.setEnabled(watch.id, false);
      await service.pump();
      expect(fetcher.calls, 0);
    });

    test('抓取失败只记错误，不抛异常也不推送', () async {
      final store = WatchStore(prefs: prefs);
      final host = _FakeHost();
      final fetcher = _FakeFetcher([])..error = const WatchException('签名错误');
      final service = WatchService(
        store: store,
        host: host,
        fetcher: fetcher,
        now: () => DateTime(2026, 11, 25, 18),
      );
      final watch = await service.create(name: '光模块');
      final result = await service.runNow(watch.id);

      expect(result!.watch.lastError, contains('签名错误'));
      expect(host.bubbles, isEmpty);
    });

    test('关键词匹配：中文包含，英文缩写按词边界（AI 不该命中 paid）', () {
      // 通过 service 的过滤行为间接验证
      expect(WatchService.debugMatches('someone paid the bill', 'ai'), isFalse);
      expect(WatchService.debugMatches('ai 服务器出货量创新高', 'ai'), isTrue);
      expect(WatchService.debugMatches('光模块需求旺盛', '光模块'), isTrue);
      expect(WatchService.debugMatches('存储芯片涨价', '光模块'), isFalse);
    });

    test('间隔下限 5 分钟；删除与开关按名称也能命中', () async {
      final store = WatchStore(prefs: prefs);
      final service = WatchService(
        store: store,
        host: _FakeHost(),
        fetcher: _FakeFetcher([]),
        now: () => DateTime(2026, 11, 25, 18),
      );
      final watch = await service.create(name: '财联社·光模块', intervalMinutes: 1);
      expect(watch.intervalMinutes, WatchService.minIntervalMinutes);

      expect(await service.setEnabled('光模块', false), isNotNull);
      expect((await store.load()).single.enabled, isFalse);

      expect(await service.remove('财联社·光模块'), isTrue);
      expect(await store.load(), isEmpty);
    });
  });

  group('设置页入口', () {
    testWidgets('简讯分组渲染完整、空态给得出示例', (tester) async {
      tester.view.physicalSize = const Size(900, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = AppController();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(const Color(0xFFF0A35E)),
        home: Scaffold(
          backgroundColor: AppColors.canvas,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SettingsTab(controller: controller),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('简讯订阅'), findsOneWidget);
      expect(find.text('新建订阅'), findsOneWidget);
      expect(find.textContaining('订阅财联社'), findsOneWidget);
      expect(tester.takeException(), isNull);

      controller.dispose();
    });
  });

  group('订阅工具', () {
    test('watch_create 一次调用即开通，watch_list 能看到', () async {
      final store = WatchStore(prefs: prefs);
      final service = WatchService(
        store: store,
        host: _FakeHost(),
        fetcher: _FakeFetcher([_item('1', '光模块扩产')]),
        now: () => DateTime(2026, 11, 25, 18),
      );

      final created = await WatchCreateTool(service).invoke({
        'name': '财联社·光模块',
        'keywords': ['光模块', '光通信', 'AI'],
        'intervalMinutes': 20,
      });
      expect(created.success, isTrue);
      expect(created.message, contains('已开通'));
      expect(created.message, contains('试抓成功'));

      final listed = await WatchListTool(service).invoke({});
      expect(listed.message, contains('财联社·光模块'));
      expect(listed.message, contains('光模块/光通信/AI'));
      expect(listed.message, contains('20 分钟'));

      final removed = await WatchDeleteTool(service).invoke({'name': '财联社·光模块'});
      expect(removed.success, isTrue);
      expect(await store.load(), isEmpty);
    });
  });
}
