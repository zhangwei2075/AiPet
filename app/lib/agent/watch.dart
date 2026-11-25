import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';
import 'brain_host.dart';
import 'memory/memory_service.dart';

/// 一条简讯。
@immutable
class WatchItem {
  const WatchItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.url,
    required this.at,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String summary;
  final String url;
  final DateTime at;
  final List<String> tags;

  String get haystack =>
      '$title $summary ${tags.join(' ')}'.toLowerCase();
}

/// 支持的资讯源。目前只接了财联社电报；加源时在这里加枚举 + 一个解析器。
enum WatchSourceKind { cailianshe }

extension WatchSourceLabel on WatchSourceKind {
  String get label => switch (this) {
        WatchSourceKind.cailianshe => '财联社电报',
      };

  static WatchSourceKind? fromName(String? name) {
    for (final kind in WatchSourceKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// 一条订阅 —— 就是主人嘴里说的「插件」。
///
/// 刻意做成「数据 + 内置抓取器」而不是让模型现写代码：模型自己写脚本既没法
/// 调度、也没法去重，最后只能卡在「找插件目录」上。这里把可变部分收敛成
/// 源 + 关键词 + 间隔，模型一次 [WatchService.create] 就能真的开通。
@immutable
class Watch {
  const Watch({
    required this.id,
    required this.name,
    required this.source,
    required this.keywords,
    required this.intervalMinutes,
    required this.enabled,
    required this.createdAt,
    this.lastRunAt,
    this.lastError,
    this.seenIds = const [],
    this.pushCount = 0,
  });

  final String id;
  final String name;
  final WatchSourceKind source;
  final List<String> keywords;
  final int intervalMinutes;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? lastRunAt;
  final String? lastError;

  /// 已经推送过的条目 id，用来去重。只留最近 300 条。
  final List<String> seenIds;
  final int pushCount;

  Watch copyWith({
    String? name,
    List<String>? keywords,
    int? intervalMinutes,
    bool? enabled,
    DateTime? lastRunAt,
    String? lastError,
    bool clearError = false,
    List<String>? seenIds,
    int? pushCount,
  }) =>
      Watch(
        id: id,
        name: name ?? this.name,
        source: source,
        keywords: keywords ?? this.keywords,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        seenIds: seenIds ?? this.seenIds,
        pushCount: pushCount ?? this.pushCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source.name,
        'keywords': keywords,
        'intervalMinutes': intervalMinutes,
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
        if (lastError != null) 'lastError': lastError,
        'seenIds': seenIds,
        'pushCount': pushCount,
      };

  factory Watch.fromJson(Map<String, dynamic> json) => Watch(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '未命名订阅',
        source: WatchSourceLabel.fromName(json['source']?.toString()) ??
            WatchSourceKind.cailianshe,
        keywords: [
          for (final k in (json['keywords'] as List?) ?? const [])
            if (k != null && k.toString().trim().isNotEmpty) k.toString().trim(),
        ],
        intervalMinutes: (json['intervalMinutes'] as num?)?.toInt() ?? 30,
        enabled: json['enabled'] != false,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lastRunAt: DateTime.tryParse(json['lastRunAt']?.toString() ?? ''),
        lastError: json['lastError']?.toString(),
        seenIds: [
          for (final id in (json['seenIds'] as List?) ?? const [])
            if (id != null) id.toString(),
        ],
        pushCount: (json['pushCount'] as num?)?.toInt() ?? 0,
      );
}

class WatchStore {
  WatchStore({SharedPreferences? prefs, String key = prefsKey})
      : _prefs = prefs,
        _key = key;

  static const String prefsKey = 'agent.watches.v1';

  SharedPreferences? _prefs;
  final String _key;

  Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<List<Watch>> load() async {
    final prefs = await _instance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Watch>[];
    try {
      return [
        for (final item in jsonDecode(raw) as List)
          Watch.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return <Watch>[];
    }
  }

  Future<void> save(List<Watch> watches) async {
    final prefs = await _instance();
    await prefs.setString(
        _key, jsonEncode([for (final w in watches) w.toJson()]));
  }
}

class WatchException implements Exception {
  const WatchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 财联社电报接口。
///
/// 签名算法是 `md5(sha1(urlencode(按 key 排序的 query)))` —— 实测 sha1、
/// md5、sha1(md5) 全部被判 `errno=10012 签名错误`，只有 md5(sha1()) 能过。
class CailiansheApi {
  static const String _base = 'https://www.cls.cn/v1/roll/get_roll_list';
  static const String sv = '8.4.6';

  static Map<String, String> params({int count = 30}) => {
        'app': 'CailianpressWeb',
        'category': '',
        'last_time': '',
        'os': 'web',
        'refresh_type': '1',
        'rn': '$count',
        'sv': sv,
      };

  static String sign(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final query = keys
        .map((k) => '$k=${Uri.encodeQueryComponent(params[k] ?? '')}')
        .join('&');
    final sha = sha1.convert(utf8.encode(query)).toString();
    return md5.convert(utf8.encode(sha)).toString();
  }

  static Uri uri({int count = 30}) {
    final p = params(count: count);
    return Uri.parse('$_base?'
        '${p.keys.map((k) => '$k=${Uri.encodeQueryComponent(p[k]!)}').join('&')}'
        '&sign=${sign(p)}');
  }

  static List<WatchItem> parse(String body) {
    final Object? data;
    try {
      data = jsonDecode(body);
    } catch (_) {
      throw const WatchException('财联社返回的不是 JSON（可能被拦截或需要验证）');
    }
    if (data is! Map) throw const WatchException('财联社返回结构异常');
    final errno = data['errno'];
    if (errno != null && '$errno' != '0') {
      throw WatchException('财联社返回 $errno：${data['msg'] ?? '未知错误'}');
    }
    final rolls = ((data['data'] as Map?)?['roll_data'] as List?) ?? const [];
    return [
      for (final raw in rolls)
        if (raw is Map) _item(raw.cast<String, dynamic>()),
    ];
  }

  static WatchItem _item(Map<String, dynamic> raw) {
    final id = '${raw['id'] ?? ''}';
    final ctime = (raw['ctime'] as num?)?.toInt() ?? 0;
    final subjects = [
      for (final s in (raw['subjects'] as List?) ?? const [])
        if (s is Map && s['subject_name'] != null) '${s['subject_name']}',
    ];
    final title = (raw['title'] ?? '').toString().trim();
    final brief = (raw['brief'] ?? raw['content'] ?? '').toString().trim();
    return WatchItem(
      id: id,
      title: title.isEmpty ? _firstLine(brief) : title,
      summary: brief,
      url: (raw['shareurl'] ?? (id.isEmpty ? '' : 'https://www.cls.cn/detail/$id'))
          .toString(),
      at: DateTime.fromMillisecondsSinceEpoch(ctime * 1000),
      tags: subjects,
    );
  }

  /// 财联社有些条目没有 title，只有 brief 里的【标题】正文，取【】里那段。
  static String _firstLine(String text) {
    final m = RegExp(r'^【(.+?)】').firstMatch(text);
    if (m != null) return m.group(1)!.trim();
    final line = text.split('\n').first.trim();
    return line.length <= 60 ? line : '${line.substring(0, 60)}…';
  }
}

/// 抓取器：直连优先，失败再回落到系统代理。
///
/// Windows 上 Dart 的 HttpClient 默认读环境变量里的代理，这台机器上那个代理
/// 已经 502 了 —— 如果不显式 DIRECT，订阅每次都会「抓取失败」，看起来就像
/// 功能没做完。DIRECT 走不通的环境（公司网必须走代理）再回落。
class WatchFetcher {
  WatchFetcher({http.Client? client, http.Client? fallback})
      : _client = client,
        _fallback = fallback;

  http.Client? _client;
  http.Client? _fallback;

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://www.cls.cn/telegraph',
    'Accept': 'application/json, text/plain, */*',
  };

  http.Client get _direct => _client ??= IOClient(io.HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..connectionTimeout = const Duration(seconds: 15));

  http.Client get _system => _fallback ??= http.Client();

  Future<String> _get(Uri uri) async {
    final errors = <String>[];
    for (final client in [_direct, _system]) {
      try {
        final res =
            await client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
        if (res.statusCode >= 400) {
          errors.add('HTTP ${res.statusCode}');
          continue;
        }
        return utf8.decode(res.bodyBytes, allowMalformed: true);
      } catch (error) {
        errors.add('$error');
      }
    }
    throw WatchException('抓取失败：${errors.join(' / ')}');
  }

  Future<List<WatchItem>> fetch(WatchSourceKind kind, {int count = 30}) async {
    switch (kind) {
      case WatchSourceKind.cailianshe:
        return CailiansheApi.parse(
            await _get(CailiansheApi.uri(count: count)));
    }
  }
}

/// 一次抓取的结果，给工具和界面共用。
@immutable
class WatchRunResult {
  const WatchRunResult({
    required this.watch,
    required this.fetched,
    required this.hits,
    required this.notified,
  });

  final Watch watch;
  final int fetched;
  final int hits;
  final bool notified;
}

/// 订阅调度：到期 → 抓取 → 关键词过滤 → 去重 → 气泡通知 + 记入记忆。
class WatchService {
  WatchService({
    required WatchStore store,
    required BrainHost host,
    WatchFetcher? fetcher,
    MemoryService? memory,
    DateTime Function()? now,
  })  : _store = store,
        _host = host,
        _fetcher = fetcher ?? WatchFetcher(),
        _memory = memory,
        _now = now ?? DateTime.now;

  static const int minIntervalMinutes = 5;
  static const int seenLimit = 300;
  static const int maxPushPerRun = 3;

  final WatchStore _store;
  final BrainHost _host;
  final WatchFetcher _fetcher;
  final MemoryService? _memory;
  final DateTime Function() _now;

  Timer? _timer;
  bool _busy = false;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(pump()),
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<List<Watch>> list() => _store.load();

  Future<Watch> create({
    required String name,
    List<String> keywords = const [],
    int intervalMinutes = 30,
    WatchSourceKind source = WatchSourceKind.cailianshe,
    bool enabled = true,
  }) async {
    final cleanName = name.trim().isEmpty ? '新订阅' : name.trim();
    final watches = [...await _store.load()];
    final watch = Watch(
      id: 'watch-${_now().microsecondsSinceEpoch}',
      name: cleanName,
      source: source,
      keywords: [
        for (final k in keywords)
          if (k.trim().isNotEmpty) k.trim(),
      ],
      intervalMinutes:
          intervalMinutes < minIntervalMinutes ? minIntervalMinutes : intervalMinutes,
      enabled: enabled,
      createdAt: _now(),
    );
    watches.add(watch);
    await _store.save(watches);
    return watch;
  }

  Future<bool> remove(String idOrName) async {
    final watches = [...await _store.load()];
    final index = _indexOf(watches, idOrName);
    if (index < 0) return false;
    watches.removeAt(index);
    await _store.save(watches);
    return true;
  }

  Future<Watch?> setEnabled(String idOrName, bool enabled) async {
    final watches = [...await _store.load()];
    final index = _indexOf(watches, idOrName);
    if (index < 0) return null;
    watches[index] = watches[index].copyWith(enabled: enabled);
    await _store.save(watches);
    return watches[index];
  }

  /// 立刻抓一次指定订阅（不看间隔）。
  Future<WatchRunResult?> runNow(String idOrName) async {
    final watches = [...await _store.load()];
    final index = _indexOf(watches, idOrName);
    if (index < 0) return null;
    final outcome = await _run(watches[index], _now());
    watches[index] = outcome.watch;
    await _store.save(watches);
    return WatchRunResult(
      watch: outcome.watch,
      fetched: outcome.fetched,
      hits: outcome.hits,
      notified: outcome.notified,
    );
  }

  /// 心跳：只处理到期的订阅，串行执行，不会并发打接口。
  Future<void> pump() async {
    if (_busy) return;
    _busy = true;
    try {
      final watches = [...await _store.load()];
      final now = _now();
      var changed = false;
      for (var i = 0; i < watches.length; i++) {
        final watch = watches[i];
        if (!watch.enabled) continue;
        final last = watch.lastRunAt;
        if (last != null &&
            now.difference(last).inMinutes < watch.intervalMinutes) {
          continue;
        }
        watches[i] = (await _run(watch, now)).watch;
        changed = true;
        // 每条跑完就存一次：抓到一半崩了也不会重复推送。
        await _store.save(watches);
      }
      if (!changed) return;
    } catch (error) {
      debugPrint('[watch] pump failed: $error');
    } finally {
      _busy = false;
    }
  }

  Future<
      ({
        Watch watch,
        int fetched,
        int hits,
        bool notified,
      })> _run(Watch watch, DateTime now) async {
    try {
      final items = await _fetcher.fetch(watch.source);
      final seen = watch.seenIds.toSet();
      final fresh = [
        for (final item in items)
          if (!seen.contains(item.id)) item,
      ];
      final first = watch.lastRunAt == null;
      // 首次往回扫 12 条再挑命中项：刚开通就刷一屏历史谁都会烦，
      // 但只看最新 1 条又常常不命中关键词，主人会以为没生效。
      final pool = first ? fresh.take(12).toList() : fresh;
      final hits = _filter(pool, watch.keywords);
      final merged = [
        ...watch.seenIds,
        for (final item in items) item.id,
      ];
      final seenIds =
          merged.length <= seenLimit ? merged : merged.sublist(merged.length - seenLimit);
      if (hits.isNotEmpty) _notify(watch, hits, first: first);
      return (
        watch: watch.copyWith(
          lastRunAt: now,
          seenIds: seenIds,
          pushCount: watch.pushCount + (hits.isEmpty ? 0 : 1),
          clearError: true,
        ),
        fetched: items.length,
        hits: hits.length,
        notified: hits.isNotEmpty,
      );
    } catch (error) {
      return (
        watch: watch.copyWith(
          lastRunAt: now,
          lastError: _short('$error'),
        ),
        fetched: 0,
        hits: 0,
        notified: false,
      );
    }
  }

  /// 关键词过滤。空关键词 = 全量。
  ///
  /// 纯英文短词（AI / GPU / CPO）按词边界匹配，否则 "AI" 会把 "paid" 也算命中。
  static List<WatchItem> _filter(List<WatchItem> items, List<String> keywords) {
    final keys = [
      for (final k in keywords)
        if (k.trim().isNotEmpty) k.trim().toLowerCase(),
    ];
    if (keys.isEmpty) return items;
    return [
      for (final item in items)
        if (keys.any((key) => _matches(item.haystack, key))) item,
    ];
  }

  static bool _matches(String haystack, String key) {
    final ascii = RegExp(r'^[a-z0-9+#.\- ]+$').hasMatch(key);
    if (!ascii || key.length > 8) return haystack.contains(key);
    final boundary = RegExp(r'(^|[^a-z0-9])' + RegExp.escape(key) + r'([^a-z0-9]|$)');
    return boundary.hasMatch(haystack);
  }

  /// 测试缝：关键词匹配规则（两边都转小写）。
  @visibleForTesting
  static bool debugMatches(String haystack, String keyword) =>
      _matches(haystack.toLowerCase(), keyword.trim().toLowerCase());

  void _notify(Watch watch, List<WatchItem> hits, {required bool first}) {
    final head = hits.first;
    final more = hits.length > 1 ? '（这次共 ${hits.length} 条）' : '';
    final text = first
        ? '「${watch.name}」开通好了，先给你看最新这条：${head.title}'
        : '「${watch.name}」有新消息$more：${head.title}';
    _host.agentBubble(_clip(text, 160), mood: PetMood.talk);
    final lines = hits.take(maxPushPerRun).map((e) => e.title).join('；');
    _memory?.recordTask(
      _host.agentPetId,
      '简讯「${watch.name}」：$lines${head.url.isEmpty ? '' : '（${head.url}）'}',
      tag: 'watch',
    );
  }

  String _short(String text) =>
      text.length <= 180 ? text : '${text.substring(0, 180)}…';

  static String _clip(String text, int limit) =>
      text.length <= limit ? text : '${text.substring(0, limit)}…';

  int _indexOf(List<Watch> watches, String idOrName) {
    final key = idOrName.trim();
    if (key.isEmpty) return watches.isEmpty ? -1 : 0;
    final byId = watches.indexWhere((w) => w.id == key);
    if (byId >= 0) return byId;
    final exact = watches.indexWhere((w) => w.name == key);
    if (exact >= 0) return exact;
    return watches.indexWhere((w) => w.name.contains(key));
  }
}
