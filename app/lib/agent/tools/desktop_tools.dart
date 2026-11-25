import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import '../permissions.dart';
import '../pet_tool.dart';
import 'system_tools.dart' show CommandRunner, SystemCommandRunner, formatShellResult;

/// user32.dll 的最小绑定。
///
/// 沿用 `AppFocusTrigger` 的做法：直接用 `dart:ffi` lookupFunction，
/// 不碰 win32 6.x 生成器里 PWSTR 的类型兼容问题。static final 是懒加载，
/// 非 Windows 平台只要不调用这些字段就不会去 open user32.dll。
class Win32Api {
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final _getForegroundWindow =
      _user32.lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');
  static final _getWindowTextW = _user32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Int32),
      int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');
  static final _findWindowW = _user32.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
  static final _showWindow =
      _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
  static final _setForegroundWindow =
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
  static final _postMessageW = _user32.lookupFunction<
      Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)>('PostMessageW');
  static final _setCursorPos =
      _user32.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('SetCursorPos');
  static final _mouseEvent = _user32.lookupFunction<
      Void Function(Uint32, Uint32, Uint32, Uint32, IntPtr),
      void Function(int, int, int, int, int)>('mouse_event');
  static final _keybdEvent = _user32.lookupFunction<
      Void Function(Uint8, Uint8, Uint32, IntPtr),
      void Function(int, int, int, int)>('keybd_event');

  static int foregroundHandle() => _getForegroundWindow();

  static String windowTitle(int hwnd) {
    if (hwnd == 0) return '';
    final buffer = calloc<Uint16>(512);
    try {
      final ptr = buffer.cast<Utf16>();
      final length = _getWindowTextW(hwnd, ptr, 512);
      return length == 0 ? '' : ptr.toDartString(length: length);
    } finally {
      calloc.free(buffer);
    }
  }

  static int findByTitle(String title) {
    final ptr = title.toNativeUtf16();
    try {
      return _findWindowW(nullptr, ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  static void show(int hwnd, int command) => _showWindow(hwnd, command);
  static void focus(int hwnd) => _setForegroundWindow(hwnd);
  static void close(int hwnd) => _postMessageW(hwnd, 0x0010, 0, 0); // WM_CLOSE
  static void moveCursor(int x, int y) => _setCursorPos(x, y);
  static void mouse(int flags, int data) => _mouseEvent(flags, 0, 0, data, 0);
  static void key(int vk, {bool up = false}) =>
      _keybdEvent(vk, 0, up ? 0x0002 : 0, 0);
}

const _swMinimize = 6;
const _swMaximize = 3;
const _swRestore = 9;
const _mouseLeftdown = 0x0002;
const _mouseLeftup = 0x0004;
const _mouseRightdown = 0x0008;
const _mouseRightup = 0x0010;
const _mouseWheel = 0x0800;

/// 窗口控制：列出有标题的窗口、按标题/句柄置前、最小化、最大化、关闭。
class WindowTool extends PetTool {
  WindowTool({CommandRunner? runner}) : _runner = runner ?? const SystemCommandRunner();

  final CommandRunner _runner;

  @override
  String get name => 'window';

  @override
  String get description =>
      '控制这台电脑上的窗口。action: list（列出窗口）/ foreground（当前窗口）/ '
      'focus / minimize / maximize / close；用 title 或 hwnd 指定目标，省略则作用于当前窗口。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['list', 'foreground', 'focus', 'minimize', 'maximize', 'close'],
          },
          'title': {'type': 'string'},
          'hwnd': {'type': 'integer'},
        },
        'required': ['action'],
      };

  @override
  AgentCapability get capability => AgentCapability.window;

  @override
  bool get slow => true;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final action = (args['action'] as String?) ?? 'foreground';
    if (action == 'list') {
      final command = Platform.isWindows
          ? "Get-Process | Where-Object { \$_.MainWindowTitle -ne '' } | "
              'Select-Object Id,ProcessName,MainWindowTitle | Format-Table -AutoSize'
          : 'ps -eo pid,comm --no-headers | head -60';
      final result = await _runner.run(command, timeoutSeconds: 20);
      return ToolResult.ok(formatShellResult(result));
    }
    if (!Platform.isWindows) {
      return const ToolResult.fail('窗口控制目前只在 Windows 上可用，其它平台请用 run_command。');
    }
    final hwnd = _resolveHandle(args);
    if (hwnd == 0) return const ToolResult.fail('找不到目标窗口，换个 title 或 hwnd 试试。');
    final title = Win32Api.windowTitle(hwnd);
    switch (action) {
      case 'foreground':
        return ToolResult.ok('当前窗口：hwnd=$hwnd title=$title');
      case 'focus':
        Win32Api.show(hwnd, _swRestore);
        Win32Api.focus(hwnd);
        return ToolResult.ok('已置前：$title');
      case 'minimize':
        Win32Api.show(hwnd, _swMinimize);
        return ToolResult.ok('已最小化：$title');
      case 'maximize':
        Win32Api.show(hwnd, _swMaximize);
        Win32Api.focus(hwnd);
        return ToolResult.ok('已最大化：$title');
      case 'close':
        Win32Api.close(hwnd);
        return ToolResult.ok('已发送关闭消息：$title');
      default:
        return const ToolResult.fail('不认识的 action。');
    }
  }

  int _resolveHandle(Map<String, dynamic> args) {
    final raw = args['hwnd'];
    if (raw is num && raw > 0) return raw.toInt();
    final title = (args['title'] as String?)?.trim() ?? '';
    if (title.isNotEmpty) return Win32Api.findByTitle(title);
    return Win32Api.foregroundHandle();
  }
}

/// 键名 → 虚拟键码。纯函数，单测覆盖。
int? virtualKeyOf(String name) {
  final key = name.trim().toLowerCase();
  const named = {
    'enter': 0x0D, 'return': 0x0D, 'tab': 0x09, 'esc': 0x1B, 'escape': 0x1B,
    'space': 0x20, 'backspace': 0x08, 'delete': 0x2E, 'del': 0x2E,
    'up': 0x26, 'down': 0x28, 'left': 0x25, 'right': 0x27,
    'home': 0x24, 'end': 0x23, 'pageup': 0x21, 'pagedown': 0x22,
    'ctrl': 0x11, 'control': 0x11, 'shift': 0x10, 'alt': 0x12, 'win': 0x5B,
    'f1': 0x70, 'f2': 0x71, 'f3': 0x72, 'f4': 0x73, 'f5': 0x74,
    'f6': 0x75, 'f7': 0x76, 'f8': 0x77, 'f9': 0x78, 'f10': 0x79,
  };
  if (named.containsKey(key)) return named[key];
  if (key.length == 1) {
    final code = key.codeUnitAt(0);
    if ((code >= 0x30 && code <= 0x39) || (code >= 0x61 && code <= 0x7A)) {
      return key.toUpperCase().codeUnitAt(0);
    }
  }
  return null;
}

/// 键鼠模拟：打字、按键、点击、移动、滚轮。
class InputTool extends PetTool {
  const InputTool();


  @override
  String get name => 'input';

  @override
  String get description =>
      '模拟键盘鼠标。action: type（输入文本，支持中文）/ key（按键或组合键，如 ctrl+c）/ '
      'click（left/right/double）/ move（x,y）/ scroll（delta）。作用于当前前台窗口。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['type', 'key', 'click', 'move', 'scroll'],
          },
          'text': {'type': 'string', 'description': 'type 用'},
          'key': {'type': 'string', 'description': 'key 用，组合键用 + 连接'},
          'button': {'type': 'string', 'enum': ['left', 'right', 'double']},
          'x': {'type': 'integer'},
          'y': {'type': 'integer'},
          'delta': {'type': 'integer'},
        },
        'required': ['action'],
      };

  @override
  AgentCapability get capability => AgentCapability.input;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    if (!Platform.isWindows) {
      return const ToolResult.fail('键鼠模拟目前只在 Windows 上可用，其它平台请用 run_command。');
    }
    final action = (args['action'] as String?) ?? '';
    switch (action) {
      case 'type':
        return _type((args['text'] as String?) ?? '');
      case 'key':
        return _key((args['key'] as String?) ?? '');
      case 'move':
        Win32Api.moveCursor((args['x'] as num?)?.toInt() ?? 0, (args['y'] as num?)?.toInt() ?? 0);
        return const ToolResult.ok('光标已移动。');
      case 'click':
        final x = args['x'];
        final y = args['y'];
        // 不传坐标就在当前光标位置点，别擅自把光标挪到屏幕中心。
        if (x is num && y is num) Win32Api.moveCursor(x.toInt(), y.toInt());
        final button = (args['button'] as String?) ?? 'left';
        if (button == 'right') {
          Win32Api.mouse(_mouseRightdown, 0);
          Win32Api.mouse(_mouseRightup, 0);
        } else {
          _leftClick();
          if (button == 'double') _leftClick();
        }
        return ToolResult.ok('已${button == 'double' ? '双击' : '点击'}。');
      case 'scroll':
        Win32Api.mouse(_mouseWheel, (args['delta'] as num?)?.toInt() ?? 120);
        return const ToolResult.ok('已滚动。');
      default:
        return const ToolResult.fail('不认识的 action。');
    }
  }

  void _leftClick() {
    Win32Api.mouse(_mouseLeftdown, 0);
    Win32Api.mouse(_mouseLeftup, 0);
  }

  Future<ToolResult> _type(String text) async {
    if (text.isEmpty) return const ToolResult.fail('text 不能为空');
    // 中文 / 任意 Unicode 只能走「剪贴板 + Ctrl+V」；用完把原内容还回去，
    // 尽量不破坏主人自己的剪贴板。
    final previous = await Clipboard.getData(Clipboard.kTextPlain);
    await Clipboard.setData(ClipboardData(text: text));
    _pressCombo([0x11, 0x56]); // Ctrl + V
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (previous?.text != null) {
      await Clipboard.setData(ClipboardData(text: previous!.text!));
    }
    return ToolResult.ok('已输入 ${text.length} 个字符。');
  }

  ToolResult _key(String spec) {
    final parts = spec.toLowerCase().split('+').map((s) => s.trim()).toList();
    final keys = <int>[];
    for (final part in parts) {
      final vk = virtualKeyOf(part);
      if (vk == null) return ToolResult.fail('不认识的键：$part');
      keys.add(vk);
    }
    if (keys.isEmpty) return const ToolResult.fail('key 不能为空');
    _pressCombo(keys);
    return ToolResult.ok('已按下：$spec');
  }

  void _pressCombo(List<int> keys) {
    for (final vk in keys) {
      Win32Api.key(vk);
    }
    for (final vk in keys.reversed) {
      Win32Api.key(vk, up: true);
    }
  }
}

/// 截屏并保存 PNG。Windows 走 PowerShell + System.Drawing（无需新增依赖）。
class ScreenshotTool extends PetTool {
  ScreenshotTool({CommandRunner? runner}) : _runner = runner ?? const SystemCommandRunner();

  final CommandRunner _runner;

  @override
  String get name => 'screenshot';

  @override
  String get description =>
      '截取当前屏幕并保存为 PNG，返回文件路径。path 可省略，默认存到临时目录。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
      };

  @override
  bool get slow => true;

  @override
  AgentCapability get capability => AgentCapability.screen;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final raw = (args['path'] as String?)?.trim() ?? '';
    final temp = Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? '.';
    final path = raw.isEmpty
        ? '$temp\\momopet_screen_${DateTime.now().millisecondsSinceEpoch}.png'
        : raw;
    final escaped = path.replaceAll("'", "''");
    if (!Platform.isWindows) {
      return const ToolResult.fail('截屏目前只在 Windows 上可用，其它平台请用 run_command。');
    }
    final command = 'Add-Type -AssemblyName System.Windows.Forms,System.Drawing; '
        '\$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; '
        '\$bmp = New-Object System.Drawing.Bitmap \$b.Width, \$b.Height; '
        '\$g = [System.Drawing.Graphics]::FromImage(\$bmp); '
        '\$g.CopyFromScreen(\$b.Location, [System.Drawing.Point]::Empty, \$b.Size); '
        "\$bmp.Save('$escaped', [System.Drawing.Imaging.ImageFormat]::Png); "
        '\$g.Dispose(); \$bmp.Dispose()';
    final result = await _runner.run(command, timeoutSeconds: 30);
    if (result.exitCode != 0) return ToolResult.fail(formatShellResult(result));
    return ToolResult.ok('已保存截屏：$path\n${formatShellResult(result)}');
  }
}

List<PetTool> buildDesktopTools({CommandRunner? runner}) => [
      WindowTool(runner: runner),
      const InputTool(),
      ScreenshotTool(runner: runner),
    ];
