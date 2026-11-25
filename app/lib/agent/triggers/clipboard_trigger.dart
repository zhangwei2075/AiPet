import 'dart:async';

import 'package:flutter/services.dart';

import 'pet_event.dart';
import 'quiet_hours.dart';

/// 剪贴板感知：轮询检测文本模式，**只留模式标签不留原文**。
///
/// 内容策略（M5 修订，见 docs/autonomy.md §4.4）：
/// · 感知默认开启（全权限方向），关「环境感知」或急停立即停止轮询；
/// · 只检测 URL / 英文句子 / 数字串三类，payload 里是 `kind` 标签和长度；
/// · 原文不进事件、不落盘、不进记忆；模型需要时自己调 `clipboard` 工具按需读取，
///   该读取同样经 ToolRuntime 审计。
class ClipboardTrigger extends PetTrigger {
  ClipboardTrigger({
    required this.isEnabled,
    Duration? interval,
    QuietPolicy? policy,
    ClipboardReader? reader,
    DateTime Function()? now,
  })  : _interval = interval ?? const Duration(seconds: 12),
        _policy = policy ?? QuietPolicy(),
        _reader = reader ?? SystemClipboardReader(),
        _now = now ?? DateTime.now;

  /// 由宿主实时读取设置开关（热改立即生效）。
  final bool Function() isEnabled;
  final Duration _interval;
  final QuietPolicy _policy;
  final ClipboardReader _reader;
  final DateTime Function() _now;

  Timer? _timer;
  String? _lastFingerprint;
  final StreamController<PetEvent> _controller = StreamController<PetEvent>.broadcast();

  @override
  String get name => 'clipboard';

  @override
  bool get enabled => isEnabled();

  @override
  Stream<PetEvent> get events => _controller.stream;

  /// 启动轮询。关掉开关时不起定时器，隐私零风险。
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(_poll()));
  }

  Future<void> pollOnceForTest() => _poll();

  Future<void> _poll() async {
    if (!enabled) return;
    final text = await _reader.read();
    if (text == null || text.trim().isEmpty) return;

    // 指纹只用于去重，不保存原文；用长度 + 前 8 字符的哈希码。
    final fingerprint = '${text.length}:${text.hashCode}';
    if (fingerprint == _lastFingerprint) return;
    _lastFingerprint = fingerprint;

    final kind = detectKind(text);
    if (kind == null) return;
    if (!_policy.allow(name, at: _now())) return;

    _controller.add(PetEvent(
      id: 'clipboard-${_now().microsecondsSinceEpoch}',
      source: PetEventSource.clipboard,
      summary: switch (kind) {
        'url' => '主人刚复制了一个网址',
        'english' => '主人刚复制了一段英文',
        'number' => '主人刚复制了一串数字',
        _ => '主人刚复制了一段文本',
      },
      payload: {'kind': kind, 'length': text.length.toString()},
      at: _now(),
    ));
  }

  /// 模式检测（纯函数，便于单测）。不做语义理解，不返回原文。
  static String? detectKind(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(text)) return 'url';
    // 英文句子：至少 12 个字母/空格，且中文字符不超过 1 个
    final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
    // 允许常见拉丁标点即可；用 Unicode 范围写法避开字符串里的引号转义。
    final latinOnly = RegExp(r'^[\x20-\x7E\u2018\u2019\u201C\u201D]+$');
    if (chinese <= 1 &&
        text.length >= 12 &&
        latinOnly.hasMatch(text) &&
        RegExp(r'[A-Za-z]').allMatches(text).length >= 8) {
      return 'english';
    }
    if (RegExp(r'^\d[\d\s\-+.]{5,}$').hasMatch(text)) return 'number';
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}

/// 测试缝：不用真的平台剪贴板。
abstract class ClipboardReader {
  Future<String?> read();
}

class SystemClipboardReader implements ClipboardReader {
  @override
  Future<String?> read() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      // 剪贴板正被别的进程占用时平台会抛 PlatformException(Unable to open clipboard)，
      // 这不是错误状态，下一轮轮询再读即可，别让它变成未捕获异常刷日志。
      return null;
    }
  }
}
