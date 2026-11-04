import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 通过 Win32 读取鼠标 / 窗口的位置，用来实现「宠物以外区域鼠标穿透」。
///
/// 全部使用物理像素，避免多显示器 + 不同缩放比例下的 DPI 换算问题。
/// 依赖 win32 6.x：返回句柄 / 布尔值的函数被包装成 `Win32Result<T>`，
/// 句柄类型是 `HWND`（extension type），所以取值统一走 `.value`。
class Win32HitTest {
  Win32HitTest(this.hwnd);

  final HWND hwnd;

  static Win32HitTest? find(String windowTitle) {
    if (!Platform.isWindows) return null;
    final title = windowTitle.toNativeUtf16();
    try {
      final handle = FindWindow(null, PCWSTR(title)).value;
      if (handle.address == 0) return null;
      return Win32HitTest(handle);
    } finally {
      calloc.free(title);
    }
  }

  RectPhysical? windowRect() {
    final rect = calloc<RECT>();
    try {
      if (!GetWindowRect(hwnd, rect).value) return null;
      return RectPhysical(
        rect.ref.left.toDouble(),
        rect.ref.top.toDouble(),
        rect.ref.right.toDouble(),
        rect.ref.bottom.toDouble(),
      );
    } finally {
      calloc.free(rect);
    }
  }

  PointPhysical? cursor() {
    final point = calloc<POINT>();
    try {
      if (!GetCursorPos(point).value) return null;
      return PointPhysical(point.ref.x.toDouble(), point.ref.y.toDouble());
    } finally {
      calloc.free(point);
    }
  }

  bool get leftButtonDown => (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;

  bool get windowVisible => IsWindowVisible(hwnd);

  bool get isForeground => GetForegroundWindow() == hwnd;
}

class RectPhysical {
  const RectPhysical(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}

class PointPhysical {
  const PointPhysical(this.x, this.y);

  final double x;
  final double y;
}
