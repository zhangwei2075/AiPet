import '../pet_tool.dart';
import '../watch.dart';

/// 订阅（简讯）工具：让智能体自己就能开通/查看/删除订阅。
///
/// 主人说「给自己做个财联社插件，定期给我股票、光模块、光通信、AI 的消息」时，
/// 模型只要调一次 `watch_create` 就真开通了 —— 不需要去找插件目录、也不需要
/// 自己写脚本（那种做法没有调度器，注定做不成，只会刷满步数后失败）。
class WatchCreateTool extends PetTool {
  WatchCreateTool(this._service);

  final WatchService _service;

  @override
  String get name => 'watch_create';

  @override
  String get description =>
      '开通一条资讯订阅（简讯）：按间隔定时抓取财联社电报，命中关键词就主动提醒主人。'
      'name 是给主人看的名字（如「财联社·光模块」）；keywords 是关键词数组'
      '（如 ["光模块","光通信","AI"]），留空表示全部推送；intervalMinutes 是抓取间隔分钟，'
      '最小 5。开通后会自动抓一次并把最新一条推给主人。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '订阅名称，给主人看的'},
          'keywords': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '关键词，命中任一即推送；空数组表示全部',
          },
          'intervalMinutes': {
            'type': 'integer',
            'description': '抓取间隔（分钟），默认 30，最小 5',
          },
        },
        'required': ['name'],
      };

  @override
  bool get slow => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return const ToolResult.fail('缺少 name');
    final keywords = [
      for (final k in (args['keywords'] as List?) ?? const [])
        if (k != null && k.toString().trim().isNotEmpty) k.toString().trim(),
    ];
    final interval = (args['intervalMinutes'] as num?)?.toInt() ??
        (args['interval'] as num?)?.toInt() ??
        30;

    final watch = await _service.create(
      name: name,
      keywords: keywords,
      intervalMinutes: interval,
    );
    // 开通即抓一次，让主人马上看到效果；抓不到也不算失败，只报原因。
    final result = await _service.runNow(watch.id);
    final head = result?.watch.lastError;
    final buffer = StringBuffer(
      '已开通「${watch.name}」：每 ${watch.intervalMinutes} 分钟抓一次'
      '${watch.source.label}${watch.keywords.isEmpty ? '，全部推送' : '，关键词 ${watch.keywords.join(' / ')}'}。',
    );
    if (head != null) {
      buffer.write(' 刚才试抓失败：$head');
    } else if (result != null) {
      buffer.write(' 试抓成功，本次拿到 ${result.fetched} 条、命中 ${result.hits} 条。');
    }
    return ToolResult.ok(buffer.toString());
  }
}

class WatchListTool extends PetTool {
  WatchListTool(this._service);

  final WatchService _service;

  @override
  String get name => 'watch_list';

  @override
  String get description => '列出当前所有资讯订阅及其状态（间隔、上次抓取、上次错误）。';

  @override
  Map<String, dynamic> get parametersSchema =>
      {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final watches = await _service.list();
    if (watches.isEmpty) return const ToolResult.ok('现在还没有任何订阅。');
    final lines = <String>[];
    for (final watch in watches) {
      final last = watch.lastRunAt == null
          ? '还没跑过'
          : '上次 ${_fmt(watch.lastRunAt!)}';
      final state = watch.enabled ? '开着' : '已暂停';
      final keys =
          watch.keywords.isEmpty ? '全部' : watch.keywords.join('/');
      lines.add('· ${watch.name}（$state，每 ${watch.intervalMinutes} 分钟，'
          '关键词 $keys，$last，已推 ${watch.pushCount} 次）'
          '${watch.lastError == null ? '' : ' 上次错误：${watch.lastError}'}');
    }
    return ToolResult.ok(lines.join('\n'));
  }

  static String _fmt(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.month}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}

class WatchRunTool extends PetTool {
  WatchRunTool(this._service);

  final WatchService _service;

  @override
  String get name => 'watch_run';

  @override
  String get description =>
      '立刻抓取一次指定订阅（不看间隔），用于验证能不能通、或主人现在就想看。'
      'name 传订阅名称；不传则抓全部。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '订阅名称，可省略'},
        },
      };

  @override
  bool get slow => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      await _service.pump();
      return const ToolResult.ok('已经让所有订阅各抓了一次，有新消息会推给你。');
    }
    final result = await _service.runNow(name);
    if (result == null) return ToolResult.fail('没有找到叫「$name」的订阅');
    final error = result.watch.lastError;
    if (error != null) return ToolResult.fail('抓取失败：$error');
    return ToolResult.ok(
      '「${result.watch.name}」抓到 ${result.fetched} 条，'
      '命中关键词 ${result.hits} 条${result.notified ? '，已经推给你了' : '，暂时没有新的'}。',
    );
  }
}

class WatchDeleteTool extends PetTool {
  WatchDeleteTool(this._service);

  final WatchService _service;

  @override
  String get name => 'watch_delete';

  @override
  String get description => '删除指定订阅。name 传订阅名称或 id。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '订阅名称或 id'},
        },
        'required': ['name'],
      };

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return const ToolResult.fail('缺少 name');
    final ok = await _service.remove(name);
    return ok
        ? ToolResult.ok('已删除订阅「$name」。')
        : ToolResult.fail('没有找到叫「$name」的订阅');
  }
}
