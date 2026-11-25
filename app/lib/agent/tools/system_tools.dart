import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../audit_log.dart';
import '../permissions.dart';
import '../pet_tool.dart';

/// 命令执行结果。抽出来是为了让 `RunCommandTool` 能在纯 Dart 单测里注入假 Runner，
/// 不必真的起进程（flutter test 环境不允许起子进程）。
class ShellResult {
  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
}

abstract class CommandRunner {
  Future<ShellResult> run(
    String command, {
    String? cwd,
    required int timeoutSeconds,
    String shell = 'auto',
  });
}

/// 真实的进程执行器。`Process.start` 而不是 `Process.run`：超时能 kill，
/// 否则一条 `ping -t` 就能把智能体永久挂住（M3 Watchdog 只管任务表，管不了子进程）。
class SystemCommandRunner implements CommandRunner {
  const SystemCommandRunner();

  /// shell 选择是纯函数，单测直接覆盖。
  static List<String> buildInvocation(String command, String shell) {
    if (shell == 'auto') shell = Platform.isWindows ? 'powershell' : 'bash';
    return switch (shell) {
      'cmd' => ['cmd.exe', '/c', command],
      'bash' => ['bash', '-lc', command],
      _ => ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
    };
  }

  @override
  Future<ShellResult> run(
    String command, {
    String? cwd,
    required int timeoutSeconds,
    String shell = 'auto',
  }) async {
    final invocation = buildInvocation(command, shell);
    final process = await Process.start(
      invocation.first,
      invocation.sublist(1),
      workingDirectory: cwd,
      // GUI 子进程由 explorer.exe 拉起（见 LaunchTool），这里只跑控制台命令。
      mode: ProcessStartMode.normal,
    );
    final out = StringBuffer();
    final err = StringBuffer();
    final decoder = const Utf8Decoder(allowMalformed: true);
    final drains = <Future<void>>[
      process.stdout.transform(decoder).forEach(out.write),
      process.stderr.transform(decoder).forEach(err.write),
    ];

    var timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      timedOut = true;
      exitCode = -1;
    }
    try {
      await Future.wait(drains).timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // stdout/stderr 没关干净也不阻塞返回。
    }
    return ShellResult(
      exitCode: exitCode,
      stdout: out.toString(),
      stderr: err.toString(),
      timedOut: timedOut,
    );
  }
}

/// 拼装工具输出：退出码 + stdout/stderr，分别截断防止刷爆模型上下文。
String formatShellResult(ShellResult result, {int outLimit = 4000, int errLimit = 2000}) {
  final out = truncate(result.stdout.trim(), outLimit);
  final err = truncate(result.stderr.trim(), errLimit);
  final buffer = StringBuffer('退出码 ${result.exitCode}');
  if (result.timedOut) buffer.write('（超时，进程已终止）');
  if (out.isNotEmpty) buffer.write('\nSTDOUT:\n$out');
  if (err.isNotEmpty) buffer.write('\nSTDERR:\n$err');
  if (out.isEmpty && err.isEmpty) buffer.write('\n（无输出）');
  return buffer.toString();
}

/// 执行任意终端命令 —— 全权限的核心工具。
class RunCommandTool extends PetTool {
  RunCommandTool({CommandRunner? runner, this.timeoutSeconds = 120})
      : _runner = runner ?? const SystemCommandRunner();

  final CommandRunner _runner;
  final int timeoutSeconds;

  @override
  String get name => 'run_command';

  @override
  String get description =>
      '在这台电脑上执行终端命令并拿到输出。Windows 默认 PowerShell，可选 cmd / bash；'
      '可指定工作目录 cwd 与超时。用于查看系统状态、跑脚本、构建项目、操作进程等任何本机任务。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': '要执行的完整命令'},
          'cwd': {'type': 'string', 'description': '工作目录，可省略'},
          'shell': {'type': 'string', 'enum': ['auto', 'powershell', 'cmd', 'bash']},
          'timeoutSeconds': {'type': 'integer', 'description': '超时秒数，默认 120'},
        },
        'required': ['command'],
      };

  @override
  bool get slow => true;

  @override
  AgentCapability get capability => AgentCapability.command;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) =>
      permissions.blockedReason((args['command'] as String?) ?? '');

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final command = (args['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) return const ToolResult.fail('命令是空的。');
    final cwd = (args['cwd'] as String?)?.trim();
    final shell = (args['shell'] as String?) ?? 'auto';
    final timeout = (args['timeoutSeconds'] as num?)?.toInt() ?? timeoutSeconds;
    try {
      final result = await _runner.run(
        command,
        cwd: (cwd == null || cwd.isEmpty) ? null : cwd,
        timeoutSeconds: timeout.clamp(1, 3600).toInt(),
        shell: shell,
      );
      return ToolResult.ok(formatShellResult(result));
    } catch (error) {
      return ToolResult.fail('命令启动失败：$error');
    }
  }
}

/// 进程查看 / 结束。比让模型现写 taskkill 更稳，也便于审计里看出「它动了进程」。
class ProcessTool extends PetTool {
  ProcessTool({CommandRunner? runner}) : _runner = runner ?? const SystemCommandRunner();

  final CommandRunner _runner;

  @override
  String get name => 'process';

  @override
  String get description =>
      '查看本机进程列表，或按 PID 结束进程。action: list / kill。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'enum': ['list', 'kill']},
          'pid': {'type': 'integer', 'description': 'kill 时必填'},
          'filter': {'type': 'string', 'description': 'list 时按名字过滤，可省略'},
        },
        'required': ['action'],
      };

  @override
  bool get slow => true;

  @override
  AgentCapability get capability => AgentCapability.process;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) {
    final action = args['action'];
    if (action == 'kill') {
      final pid = args['pid'];
      if (pid is! num || pid <= 0) return 'kill 需要正整数 pid';
    }
    return null;
  }

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final isWindows = Platform.isWindows;
    final action = (args['action'] as String?) ?? 'list';
    final String command;
    if (action == 'kill') {
      final pid = (args['pid'] as num).toInt();
      command = isWindows ? 'taskkill /PID $pid /F' : 'kill -9 $pid';
    } else {
      final filter = (args['filter'] as String?)?.trim() ?? '';
      // 去掉引号与管道符，避免过滤词被拼成第二段命令。
      final safe = filter.replaceAll(RegExp('[\u0027\u0022;|&]'), '');
      command = isWindows
          ? (safe.isEmpty
              ? 'Get-Process | Select-Object -First 60 Id,ProcessName,CPU | Format-Table -AutoSize'
              : "Get-Process | Where-Object { \$_.ProcessName -like '*$safe*' } | Select-Object Id,ProcessName,CPU")
          : (safe.isEmpty ? 'ps aux | head -60' : 'ps aux | grep -i "$safe"');
    }
    final result = await _runner.run(command, timeoutSeconds: 30);
    return ToolResult.ok(formatShellResult(result));
  }
}

/// 启动程序 / 打开文件 / 打开网址。
///
/// Windows 上一律经 `explorer.exe` 拉起：直接 Start-Process 出来的 GUI 子进程
/// 会被宿主 Job 对象回收（2026-11-24 构建实测结论，见 docs/architecture.md）。
class LaunchTool extends PetTool {
  LaunchTool({CommandRunner? runner}) : _runner = runner ?? const SystemCommandRunner();

  final CommandRunner _runner;

  @override
  String get name => 'launch';

  @override
  String get description =>
      '启动一个程序、打开一个文件或打开网址。target 传绝对路径、可执行文件名或 URL；'
      'arguments 可附加启动参数。Windows 经由 explorer.exe 启动，避免子进程被回收。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'target': {'type': 'string'},
          'arguments': {'type': 'string'},
        },
        'required': ['target'],
      };

  @override
  bool get slow => true;

  @override
  AgentCapability get capability => AgentCapability.launch;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) {
    final target = (args['target'] as String?)?.trim() ?? '';
    if (target.isEmpty) return 'target 不能为空';
    return permissions.blockedReason(target);
  }

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final target = (args['target'] as String?)?.trim() ?? '';
    final extra = (args['arguments'] as String?)?.trim() ?? '';
    final escaped = target.replaceAll("'", "''");
    final String command;
    if (Platform.isWindows) {
      final arg = extra.isEmpty ? escaped : "$escaped $extra".replaceAll("'", "''");
      command = "Start-Process -FilePath 'explorer.exe' -ArgumentList '$arg'";
    } else if (Platform.isMacOS) {
      command = "open '$escaped'";
    } else {
      command = "xdg-open '$escaped'";
    }
    final result = await _runner.run(command, timeoutSeconds: 20);
    return ToolResult.ok('已请求启动：$target\n${formatShellResult(result)}');
  }
}

/// 任意 HTTP 请求：让智能体能查接口、调本地服务、拉网页。
class HttpRequestTool extends PetTool {
  HttpRequestTool({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'http_request';

  @override
  String get description =>
      '发起 HTTP 请求并返回响应。可指定 method / url / headers / body，用于查询接口、'
      '调用本机服务或抓取网页内容。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'method': {'type': 'string', 'enum': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD']},
          'url': {'type': 'string'},
          'headers': {'type': 'object', 'description': '请求头键值对'},
          'body': {'type': 'string'},
        },
        'required': ['url'],
      };

  @override
  bool get slow => true;

  @override
  AgentCapability get capability => AgentCapability.network;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) {
    final url = (args['url'] as String?)?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) return 'url 不合法';
    return null;
  }

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final method = ((args['method'] as String?) ?? 'GET').toUpperCase();
    final uri = Uri.parse((args['url'] as String).trim());
    final request = http.Request(method, uri);
    final headers = args['headers'];
    if (headers is Map) {
      headers.forEach((key, value) => request.headers[key.toString()] = value.toString());
    }
    final body = args['body'];
    if (body != null && body.toString().isNotEmpty) {
      request.body = body.toString();
      request.headers.putIfAbsent('Content-Type', () => 'application/json; charset=utf-8');
    }
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      final text = truncate(utf8.decode(response.bodyBytes, allowMalformed: true), 4000);
      return ToolResult.ok('HTTP ${response.statusCode}\n$text');
    } catch (error) {
      return ToolResult.fail('请求失败：$error');
    }
  }
}

/// M5 新增的本机工具清单，供装配与 UI 复用。
List<PetTool> buildSystemTools({CommandRunner? runner, http.Client? client}) => [
      RunCommandTool(runner: runner),
      ProcessTool(runner: runner),
      LaunchTool(runner: runner),
      HttpRequestTool(client: client),
    ];
