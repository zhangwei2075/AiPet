import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'pet_event.dart';
import 'quiet_hours.dart';

/// 前台窗口大类：只判断类别，不保留窗口标题原文（隐私要求）。
enum AppCategory { browser, editor, office, game, chat, unknown }

/// 前台应用感知：每 15 秒看一次当前窗口属于哪一类。
///
/// 用途是「预判式关怀」的输入——比如在编辑器里待很久，宠物可以问
/// 「写代码累了吧」，而不是-going到具体窗口标题。
/// Windows 用 win32 GetForegroundWindow + GetWindowText；其它平台直接不启用。
class AppFocusTrigger extends PetTrigger {
  AppFocusTrigger({
    required this.isEnabled,
    Duration? interval,
    QuietPolicy? policy,
    FocusReader? reader,
    DateTime Function()? now,
  })  : _interval = interval ?? const Duration(seconds: 15),
        _policy = policy ?? QuietPolicy(),
        _reader = reader ?? (Platform.isWindows ? Win32FocusReader() : const NoopFocusReader()),
        _now = now ?? DateTime.now;

  final bool Function() isEnabled;
  final Duration _interval;
  final QuietPolicy _policy;
  final FocusReader _reader;
  final DateTime Function() _now;

  Timer? _timer;
  AppCategory? _lastCategory;
  final StreamController<PetEvent> _controller = StreamController<PetEvent>.broadcast();

  @override
  String get name => 'app_focus';

  @override
  bool get enabled => isEnabled() && _reader.available;

  @override
  Stream<PetEvent> get events => _controller.stream;

  void start() {
    if (_timer != null || !_reader.available) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(_poll()));
  }

  Future<void> pollOnceForTest() => _poll();

  Future<void> _poll() async {
    if (!enabled) return;
    final title = await _reader.foregroundTitle();
    if (title == null || title.trim().isEmpty) return;
    final category = categorize(title);
    // 同一应用大类持续期间不重复触发；切到新类别才算新事件。
    if (category == _lastCategory) return;
    _lastCategory = category;
    if (category == AppCategory.unknown) return;
    final now = _now();
    if (!_policy.allow(name, at: now)) return;

    _controller.add(PetEvent(
      id: 'focus-${now.microsecondsSinceEpoch}',
      source: PetEventSource.appFocus,
      summary: switch (category) {
        AppCategory.browser => '主人正在上网',
        AppCategory.editor => '主人正在写代码',
        AppCategory.office => '主人在处理文档',
        AppCategory.game => '主人在玩游戏',
        AppCategory.chat => '主人在聊天',
        AppCategory.unknown => '',
      },
      payload: {'category': category.name},
      at: now,
    ));
  }

  /// 纯函数分类：常见应用标题关键词 → 大类。不返回标题本身。
  static AppCategory categorize(String title) {
    final t = title.toLowerCase();
    if (RegExp(r'chrome|edge|firefox|safari|browser|浏览器').hasMatch(t)) return AppCategory.browser;
    if (RegExp(r'visual studio|android studio|vscode|\bcode\b|idea|pycharm|terminal|powershell|cmd|xcode').hasMatch(t)) {
      return AppCategory.editor;
    }
    if (RegExp(r'word|excel|powerpoint|wps|libreoffice|钉钉|飞书|企业微信').hasMatch(t)) return AppCategory.office;
    if (RegExp(r'steam|epic|game|游戏|原神|英雄联盟').hasMatch(t)) return AppCategory.game;
    if (RegExp(r'微信|qq|slack|discord|telegram|钉钉').hasMatch(t)) return AppCategory.chat;
    return AppCategory.unknown;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}

abstract class FocusReader {
  bool get available;
  Future<String?> foregroundTitle();
}

class NoopFocusReader implements FocusReader {
  const NoopFocusReader();

  @override
  bool get available => false;

  @override
  Future<String?> foregroundTitle() async => null;
}

/// 直接用 dart:ffi 调 user32.dll，避免 win32 6.x 生成器里 PWSTR 类型的兼容问题。
/// 只在这里用原生调用，其余代码纯 Dart 可测。
class Win32FocusReader implements FocusReader {
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final _getForegroundWindow =
      _user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
  static final _getWindowTextW = _user32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');

  @override
  bool get available => Platform.isWindows;

  @override
  Future<String?> foregroundTitle() async {
    if (!Platform.isWindows) return null;
    final hwnd = _getForegroundWindow();
    if (hwnd == 0) return null;
    final buffer = calloc<Uint16>(512);
    try {
      final ptr = buffer.cast<Utf16>();
      final length = _getWindowTextW(hwnd, ptr, 512);
      if (length == 0) return null;
      return ptr.toDartString(length: length);
    } finally {
      calloc.free(buffer);
    }
  }
}
