import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_mode.dart';
import 'display_bounds.dart';
import 'win32_hit_test.dart';

/// 桌面窗口生命周期 / 尺寸 / 置顶 / 穿透 / 拖动。
///
/// Windows 的透明无边框窗口依赖 flutter_acrylic 的 transparent effect，
/// 详细说明见 docs/platforms.md。
class WindowService with WindowListener {
  static const String windowTitle = 'MomoPetDesktop';

  /// 宠物本体占用的区域（由 PetStage 上报）。
  final ValueNotifier<Rect> hitRect = ValueNotifier<Rect>(Rect.zero);

  /// 气泡 / 右上角工具按钮等「除宠物以外还需要点击」的区域（由 PetView 上报）。
  /// 不把它们算进来，鼠标穿透会让这些按钮永远点不到。
  final ValueNotifier<Rect> uiRect = ValueNotifier<Rect>(Rect.zero);

  bool _initialized = false;
  bool _clickThrough = true;
  bool _ignoring = false;
  bool _dragging = false;
  bool _ticking = false;
  WindowMode _mode = WindowMode.pet;
  Timer? _hitTimer;
  Win32HitTest? _win32;
  VoidCallback? onQuit;

  /// 拖动过程中每帧的位移（逻辑像素），用于切换走路动画和朝向。
  void Function(Offset delta)? onDragMove;

  bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get isMobile => Platform.isAndroid || Platform.isIOS;
  bool get isDragging => _dragging;

  Size sizeFor(WindowMode mode, double scale) {
    // scale = 相对设计尺寸（精灵 300px）的倍数，默认 0.25。
    // 窗口在精灵之外还要给气泡/按钮留出空间（窗口本身透明，不影响视觉大小）。
    final petWidth = math.max(220.0, 300 * scale + 80);
    final petHeight = math.max(280.0, petWidth * 480 / 380);
    return switch (mode) {
      WindowMode.pet => Size(petWidth, petHeight),
      WindowMode.chat => Size(math.max(410, petWidth), 660),
      WindowMode.panel => const Size(900, 680),
    };
  }

  Future<void> init({
    required double scale,
    required bool clickThrough,
    String? savedPosition,
  }) async {
    if (!isDesktop || _initialized) return;
    _clickThrough = clickThrough;

    await windowManager.ensureInitialized();
    try {
      await acrylic.Window.initialize();
      await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    } catch (error) {
      debugPrint('acrylic unavailable: $error');
    }

    final size = sizeFor(WindowMode.pet, scale);
    final options = WindowOptions(
      size: size,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
      title: windowTitle,
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setHasShadow(false);
      await windowManager.setResizable(false);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setTitle(windowTitle);
      await windowManager.show();
    });
    windowManager.addListener(this);
    _initialized = true;
    _win32 = Win32HitTest.find(windowTitle);

    final primaryArea = DisplayArea.fromDisplay(await screenRetriever.getPrimaryDisplay());
    final saved = _parsePosition(savedPosition);
    final target = saved ??
        Offset(
          primaryArea.bounds.right - size.width - 32,
          primaryArea.bounds.bottom - size.height - 56,
        );
    final area = saved == null ? primaryArea.bounds : await _displayBoundsForWindow(saved, size);
    await windowManager.setPosition(clampToArea(target, size, area));
    startHitTesting();
  }

  Offset? _parsePosition(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  /// 窗口当前所在显示器的工作区；拿不到就退回主屏。
  Future<Rect> _displayBoundsForWindow(Offset position, Size size) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      final areas = displays.map(DisplayArea.fromDisplay).toList();
      final match = displayForRect(position & size, areas);
      if (match != null) return match.bounds;
    } catch (error) {
      debugPrint('getAllDisplays failed: $error');
    }
    final primary = await screenRetriever.getPrimaryDisplay();
    return DisplayArea.fromDisplay(primary).bounds;
  }

  String? get positionString {
    // 由控制器在退出前调用
    return _lastPositionString;
  }

  String? _lastPositionString;

  Future<void> rememberPosition() async {
    if (!isDesktop || !_initialized) return;
    final position = await windowManager.getPosition();
    _lastPositionString = '${position.dx.round()},${position.dy.round()}';
  }

  Future<void> applyMode(WindowMode mode, {required double scale}) async {
    _mode = mode;
    if (!isDesktop || !_initialized) return;
    final size = sizeFor(mode, scale);
    final oldSize = await windowManager.getSize();
    final oldPosition = await windowManager.getPosition();
    final area = await _displayBoundsForWindow(oldPosition, oldSize);

    final target = clampToArea(
      Offset(
        oldPosition.dx + (oldSize.width - size.width) / 2,
        oldPosition.dy + (oldSize.height - size.height) * 0.35,
      ),
      size,
      area,
    );

    await windowManager.setSize(size);
    await windowManager.setPosition(target);
    if (mode != WindowMode.pet) await _setIgnore(false);
  }

  Future<void> setAlwaysOnTop(bool value) async {
    if (!isDesktop || !_initialized) return;
    await windowManager.setAlwaysOnTop(value);
  }

  Future<void> setClickThrough(bool value) async {
    _clickThrough = value;
    if (!value) await _setIgnore(false);
  }

  Future<void> _setIgnore(bool ignore) async {
    if (!isDesktop || !_initialized) return;
    if (_ignoring == ignore) return;
    _ignoring = ignore;
    try {
      await windowManager.setIgnoreMouseEvents(ignore);
    } catch (error) {
      debugPrint('setIgnoreMouseEvents failed: $error');
    }
  }

  void startHitTesting() {
    if (!Platform.isWindows) return;
    _hitTimer?.cancel();
    _win32 ??= Win32HitTest.find(windowTitle);
    _hitTimer = Timer.periodic(const Duration(milliseconds: 120), (_) => _tickHitTest());
  }

  Future<void> _tickHitTest() async {
    if (_ticking || _dragging || !_initialized) return;
    if (!_clickThrough || _mode != WindowMode.pet) {
      await _setIgnore(false);
      return;
    }
    final win = _win32;
    if (win == null) return;
    _ticking = true;
    try {
      final rect = win.windowRect();
      final cursor = win.cursor();
      if (rect == null || cursor == null || !win.windowVisible) return;
      final logical = await windowManager.getSize();
      if (logical.width <= 1) return;
      final dpr = rect.width / logical.width;
      if (dpr <= 0) return;
      final local = Offset(
        (cursor.x - rect.left) / dpr,
        (cursor.y - rect.top) / dpr,
      );
      bool hits(Rect rect) => rect.width > 4 && rect.height > 4 && rect.inflate(12).contains(local);
      final inside = hits(hitRect.value) || hits(uiRect.value);
      // _ignoring 表示当前是穿透状态
      if (inside == _ignoring) {
        await _setIgnore(!inside);
      }
    } catch (error) {
      debugPrint('hit test error: $error');
    } finally {
      _ticking = false;
    }
  }

  /// Windows 下用鼠标位置手动移动窗口：
  /// 比 `startDragging()`（WM_NCLBUTTONDOWN 模态循环）更可控，
  /// 拖动过程中还能继续播放「被拎起来」的动画。
  Future<void> beginDrag() async {
    if (!isDesktop || !_initialized) return;
    _dragging = true;
    await _setIgnore(false);

    if (Platform.isWindows) {
      final win = _win32;
      final rect = win?.windowRect();
      final cursor = win?.cursor();
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      if (win == null || rect == null || cursor == null || size.width < 1) {
        _dragging = false;
        return;
      }
      final dpr = rect.width / size.width;
      if (dpr <= 0) {
        _dragging = false;
        return;
      }
      _dragCursor = cursor;
      _dragWindow = position;
      _dragDpr = dpr;
      _lastDragDelta = Offset.zero;
      _dragTimer?.cancel();
      _dragTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        final now = _win32?.cursor();
        if (now == null || _dragCursor == null || _dragWindow == null) return;
        final dx = (now.x - _dragCursor!.x) / _dragDpr;
        final dy = (now.y - _dragCursor!.y) / _dragDpr;
        windowManager.setPosition(Offset(_dragWindow!.dx + dx, _dragWindow!.dy + dy));
        final total = Offset(dx, dy);
        final delta = total - _lastDragDelta;
        if (delta.distance > 0.5) {
          _lastDragDelta = total;
          onDragMove?.call(delta);
        }
      });
      return;
    }

    try {
      await windowManager.startDragging();
    } catch (error) {
      debugPrint('startDragging failed: $error');
      _dragging = false;
    }
  }

  Timer? _dragTimer;
  PointPhysical? _dragCursor;
  Offset? _dragWindow;
  double _dragDpr = 1;
  Offset _lastDragDelta = Offset.zero;

  bool get mouseButtonDown => _win32?.leftButtonDown ?? false;

  void endDrag() {
    _dragging = false;
    _dragTimer?.cancel();
    _dragTimer = null;
    _dragCursor = null;
    _dragWindow = null;
    _lastDragDelta = Offset.zero;
  }

  /// 空闲时横向小步走动，让宠物「活」起来。
  /// 横向滑动 [dx] 逻辑像素。[duration] 越短滑得越快（跑就是短时长大位移）。
  /// 边界按窗口当前所在显示器计算，所以拖到副屏后也会在副屏里走。
  Future<void> glideBy(double dx, {Duration duration = const Duration(milliseconds: 580)}) async {
    if (!isDesktop || !_initialized || _dragging) return;
    final start = await windowManager.getPosition();
    final size = await windowManager.getSize();
    final area = await _displayBoundsForWindow(start, size);
    final target = clampGlideTarget(start: start, dx: dx, windowSize: size, area: area);
    if ((target.dx - start.dx).abs() < 2) return;
    const steps = 16;
    final stepDelay = duration ~/ steps;
    for (var i = 1; i <= steps; i++) {
      if (_dragging) return;
      final t = i / steps;
      final eased = t * t * (3 - 2 * t);
      await windowManager.setPosition(Offset(start.dx + (target.dx - start.dx) * eased, start.dy));
      await Future<void>.delayed(stepDelay);
    }
  }

  Future<void> hide() async {
    if (isDesktop && _initialized) await windowManager.hide();
  }

  Future<void> show() async {
    if (isDesktop && _initialized) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  Future<void> focus() async {
    if (isDesktop && _initialized) await windowManager.focus();
  }

  Future<void> quit() async {
    if (isDesktop && _initialized) {
      await rememberPosition();
      onQuit?.call();
      // 走 WM_CLOSE 自然销毁。不要用 windowManager.destroy()（内部是
      // PostQuitMessage(0)）：窗口还活着就退出消息循环，runner 拆卸
      // FlutterDesktopViewController 时窗口过程还会把消息转发给已释放
      // 的引擎，导致 APPCRASH（flutter_windows.dll）。
      await windowManager.close();
    }
  }

  void dispose() {
    _hitTimer?.cancel();
    if (_initialized) windowManager.removeListener(this);
  }

  @override
  void onWindowClose() {
    onQuit?.call();
  }
}
