import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../audit_log.dart';
import '../permissions.dart';
import '../pet_tool.dart';

/// 路径归一化：支持 `~` 展开（Windows USERPROFILE / 其它平台 HOME）。
/// 纯函数，单测直接覆盖。
String resolvePath(String raw) {
  var path = raw.trim();
  if (path == '~' || path.startsWith('~/') || path.startsWith('~\\')) {
    final home = Platform.isWindows
        ? (Platform.environment['USERPROFILE'] ?? '')
        : (Platform.environment['HOME'] ?? '');
    path = '$home${path.substring(1)}';
  }
  return path;
}

/// 通配符转正则：只支持 `*`，够覆盖 `*.log` / `*.dart` 这类常见用法。
RegExp globToRegExp(String pattern) {
  final buffer = StringBuffer('^');
  for (final unit in pattern.codeUnits) {
    final ch = String.fromCharCode(unit);
    buffer.write(ch == '*' ? '.*' : RegExp.escape(ch));
  }
  buffer.write(r'$'); // 正则结尾锚点，别写成字符串插值
  return RegExp(buffer.toString(), caseSensitive: false);
}

/// 读文件。大文件只取前 [maxChars]，避免把整份日志塞进模型上下文。
class FileReadTool extends PetTool {
  const FileReadTool();

  @override
  String get name => 'file_read';

  @override
  String get description =>
      '读取本机任意文本文件的内容。path 支持绝对路径或 ~ 开头；可用 maxChars 限制长度。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'maxChars': {'type': 'integer', 'description': '默认 12000'},
        },
        'required': ['path'],
      };

  @override
  AgentCapability get capability => AgentCapability.fileRead;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final raw = (args['path'] as String?) ?? '';
    if (raw.trim().isEmpty) return const ToolResult.fail('path 不能为空');
    final file = File(resolvePath(raw));
    if (!await file.exists()) return ToolResult.fail('文件不存在：${file.path}');
    final maxChars = ((args['maxChars'] as num?)?.toInt() ?? 12000).clamp(100, 200000).toInt();
    try {
      final size = await file.length();
      String text;
      try {
        text = await file.readAsString();
      } catch (_) {
        text = latin1.decode(await file.readAsBytes(), allowInvalid: true);
      }
      final clipped = truncate(text, maxChars);
      return ToolResult.ok('${file.path}（$size 字节）\n$clipped');
    } catch (error) {
      return ToolResult.fail('读取失败：$error');
    }
  }
}

/// 写文件：自动创建父目录，支持追加。
class FileWriteTool extends PetTool {
  const FileWriteTool();

  @override
  String get name => 'file_write';

  @override
  String get description =>
      '把文本写入本机文件（不存在则创建，自动建父目录）。append=true 时追加到末尾。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
          'append': {'type': 'boolean'},
        },
        'required': ['path', 'content'],
      };

  @override
  AgentCapability get capability => AgentCapability.fileWrite;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) =>
      ((args['path'] as String?) ?? '').trim().isEmpty ? 'path 不能为空' : null;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final file = File(resolvePath((args['path'] as String?) ?? ''));
    final content = (args['content'] as String?) ?? '';
    final append = args['append'] == true;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(content, mode: append ? FileMode.append : FileMode.write);
      return ToolResult.ok('已${append ? '追加到' : '写入'} ${file.path}（${content.length} 字符）');
    } catch (error) {
      return ToolResult.fail('写入失败：$error');
    }
  }
}

/// 列目录。pattern 支持 `*` 通配，recursive 控制是否递归。
class FileListTool extends PetTool {
  const FileListTool();

  @override
  String get name => 'file_list';

  @override
  String get description =>
      '列出本机目录下的文件与子目录。pattern 可传 `*.log` 之类的通配符，limit 控制条数。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'pattern': {'type': 'string'},
          'recursive': {'type': 'boolean'},
          'limit': {'type': 'integer'},
        },
        'required': ['path'],
      };

  @override
  AgentCapability get capability => AgentCapability.fileRead;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final dir = Directory(resolvePath((args['path'] as String?) ?? ''));
    if (!await dir.exists()) return ToolResult.fail('目录不存在：${dir.path}');
    final pattern = (args['pattern'] as String?)?.trim() ?? '';
    final regex = pattern.isEmpty ? null : globToRegExp(pattern);
    final recursive = args['recursive'] == true;
    final limit = ((args['limit'] as num?)?.toInt() ?? 200).clamp(1, 2000).toInt();
    try {
      final lines = <String>[];
      await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (regex != null && !regex.hasMatch(name)) continue;
        final kind = entity is Directory ? 'DIR ' : 'FILE';
        lines.add('$kind ${entity.path}');
        if (lines.length >= limit) break;
      }
      return ToolResult.ok(lines.isEmpty ? '（没有匹配项）' : lines.join('\n'));
    } catch (error) {
      return ToolResult.fail('列目录失败：$error');
    }
  }
}

/// 在目录里搜文本内容：逐文件读前 512KB，返回命中行。
class FileSearchTool extends PetTool {
  const FileSearchTool();

  @override
  String get name => 'file_search';

  @override
  String get description =>
      '在本机目录的文本文件里搜索关键字，返回「路径:行号:内容」。可传 pattern 过滤文件名。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'query': {'type': 'string'},
          'pattern': {'type': 'string'},
          'recursive': {'type': 'boolean'},
          'limit': {'type': 'integer'},
        },
        'required': ['path', 'query'],
      };

  @override
  AgentCapability get capability => AgentCapability.fileRead;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final dir = Directory(resolvePath((args['path'] as String?) ?? ''));
    final query = (args['query'] as String?) ?? '';
    if (query.trim().isEmpty) return const ToolResult.fail('query 不能为空');
    if (!await dir.exists()) return ToolResult.fail('目录不存在：${dir.path}');
    final pattern = (args['pattern'] as String?)?.trim() ?? '';
    final regex = pattern.isEmpty ? null : globToRegExp(pattern);
    final recursive = args['recursive'] != false;
    final limit = ((args['limit'] as num?)?.toInt() ?? 60).clamp(1, 500).toInt();
    final hits = <String>[];
    try {
      await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (regex != null && !regex.hasMatch(name)) continue;
        if (await entity.length() > 512 * 1024) continue;
        final text = await entity.readAsString().catchError((_) => '');
        if (text.isEmpty) continue;
        final lines = const LineSplitter().convert(text);
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].toLowerCase().contains(query.toLowerCase())) continue;
          hits.add('${entity.path}:${i + 1}: ${truncate(lines[i].trim(), 200)}');
          if (hits.length >= limit) break;
        }
        if (hits.length >= limit) break;
      }
      return ToolResult.ok(hits.isEmpty ? '没有找到「$query」。' : hits.join('\n'));
    } catch (error) {
      return ToolResult.fail('搜索失败：$error');
    }
  }
}

/// 删除**单个文件**。目录删除刻意不提供工具：需要时用 `run_command` 明确写出整条命令，
/// 由命令黑名单与审计兜住，避免「参数一填错就递归删掉整个目录」。
class FileDeleteTool extends PetTool {
  const FileDeleteTool();

  @override
  String get name => 'file_delete';

  @override
  String get description => '删除本机一个文件。只接受文件，不接受目录；删除不可恢复。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      };

  @override
  AgentCapability get capability => AgentCapability.fileDelete;

  @override
  String? validate(Map<String, dynamic> args, AgentPermissions permissions) {
    final raw = (args['path'] as String?) ?? '';
    if (raw.trim().isEmpty) return 'path 不能为空';
    final path = resolvePath(raw);
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.directory) {
      return '只删单个文件，不接受目录';
    }
    return null;
  }

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final file = File(resolvePath((args['path'] as String?) ?? ''));
    if (!await file.exists()) return ToolResult.fail('文件不存在：${file.path}');
    try {
      await file.delete();
      return ToolResult.ok('已删除 ${file.path}');
    } catch (error) {
      return ToolResult.fail('删除失败：$error');
    }
  }
}

/// 写剪贴板（M1 只有读，M5 补上写，配合键鼠工具可做「复制 → 粘贴」）。
class ClipboardWriteTool extends PetTool {
  const ClipboardWriteTool();

  @override
  String get name => 'clipboard_write';

  @override
  String get description => '把文本写入系统剪贴板。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      };

  @override
  AgentCapability get capability => AgentCapability.clipboardWrite;

  @override
  Future<ToolResult> invoke(Map<String, dynamic> args) async {
    final text = (args['text'] as String?) ?? '';
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ToolResult.ok('已把 ${text.length} 个字符放进剪贴板。');
    } catch (error) {
      return ToolResult.fail('写剪贴板失败：$error');
    }
  }
}

List<PetTool> buildFileTools() => const [
      FileReadTool(),
      FileWriteTool(),
      FileListTool(),
      FileSearchTool(),
      FileDeleteTool(),
      ClipboardWriteTool(),
    ];
