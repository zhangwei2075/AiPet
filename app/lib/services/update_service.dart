import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 版本检查接口返回的一条更新信息。
///
/// 支持两种 JSON：
/// ```json
/// { "version": "0.2.0", "url": "https://.../MomoPet.msix", "notes": "..." }
/// ```
/// 或按平台分组：
/// ```json
/// { "version": "0.2.0", "windows": { "url": "...", "sha256": "...", "size": 123 } }
/// ```
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.notes = '',
    this.sha256,
    this.size,
  });

  final String version;
  final String downloadUrl;
  final String notes;
  final String? sha256;
  final int? size;

  /// 只有安装包才走“下载并安装”，其余链接打开下载页。
  bool get isInstaller {
    final path = (Uri.tryParse(downloadUrl)?.path ?? downloadUrl).toLowerCase();
    return path.endsWith('.msix') ||
        path.endsWith('.msixbundle') ||
        path.endsWith('.appx') ||
        path.endsWith('.exe');
  }

  static UpdateInfo? fromJson(Map<String, dynamic> json) {
    final windows = json['windows'];
    final target = windows is Map ? Map<String, dynamic>.from(windows) : json;
    final version = (json['version'] ?? target['version'])?.toString().trim();
    final url = (target['url'] ??
            target['downloadUrl'] ??
            target['download_url'] ??
            json['url'])
        ?.toString()
        .trim();
    if (version == null || version.isEmpty || url == null || url.isEmpty) {
      return null;
    }

    final notes = target['notes'] ?? target['releaseNotes'] ?? json['notes'];
    final sha = (target['sha256'] ?? json['sha256'])?.toString().trim().toLowerCase();
    final rawSize = target['size'] ?? json['size'];
    return UpdateInfo(
      version: version,
      downloadUrl: url,
      notes: notes?.toString() ?? '',
      sha256: (sha == null || sha.isEmpty) ? null : sha,
      size: rawSize is num ? rawSize.toInt() : int.tryParse(rawSize?.toString() ?? ''),
    );
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 版本检查 / 下载 / 启动安装。网络层可注入，方便单测。
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.trim();
      return build.isEmpty ? info.version : '${info.version}+$build';
    } catch (error) {
      debugPrint('PackageInfo unavailable: $error');
      return '0.1.0';
    }
  }

  Future<UpdateInfo?> check({
    required String manifestUrl,
    required String currentVersion,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.tryParse(manifestUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const UpdateException('版本检查地址必须是 http/https URL');
    }

    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw UpdateException('版本检查失败：HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const UpdateException('版本检查返回的不是 JSON');
    }
    if (decoded is! Map) {
      throw const UpdateException('版本信息格式不对');
    }

    final info = UpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
    if (info == null) {
      throw const UpdateException('版本信息缺少 version 或下载地址');
    }
    return isNewerVersion(info.version, currentVersion) ? info : null;
  }

  Future<File> download(
    UpdateInfo info, {
    required Directory directory,
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = Uri.tryParse(info.downloadUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const UpdateException('下载地址必须是 http/https URL');
    }

    final response = await _client.send(http.Request('GET', uri));
    if (response.statusCode != 200) {
      throw UpdateException('下载失败：HTTP ${response.statusCode}');
    }
    final total = response.contentLength;
    if (info.size != null && total != null && total != info.size) {
      throw UpdateException('安装包大小不一致（$total != ${info.size}）');
    }

    final file = File('${directory.path}${Platform.pathSeparator}${_fileName(uri, info.version)}');
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } catch (error) {
      await sink.close();
      if (await file.exists()) await file.delete();
      throw UpdateException('下载中断：$error');
    }
    await sink.close();

    if (info.size != null && received != info.size) {
      await file.delete();
      throw UpdateException('安装包大小不一致（$received != ${info.size}）');
    }
    if (info.sha256 != null) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != info.sha256) {
        await file.delete();
        throw const UpdateException('安装包校验失败（sha256 不匹配）');
      }
    }
    return file;
  }

  Future<void> launchInstaller(File file) async {
    if (!Platform.isWindows) {
      throw const UpdateException('自动安装仅支持 Windows');
    }
    if (file.path.toLowerCase().endsWith('.exe')) {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
      return;
    }
    // msix / msixbundle / appx 交给系统 App Installer
    final result = await Process.run('cmd', ['/c', 'start', '', file.path]);
    if (result.exitCode != 0) {
      throw UpdateException('无法启动安装程序：${result.stderr}');
    }
  }

  Future<void> openDownloadPage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const UpdateException('下载页地址必须是 http/https URL');
    }
    final result = Platform.isWindows
        ? await Process.run('cmd', ['/c', 'start', '', url])
        : await Process.run('xdg-open', [url]);
    if (result.exitCode != 0) {
      throw UpdateException('无法打开下载页：${result.stderr}');
    }
  }

  void dispose() => _client.close();

  String _fileName(Uri uri, String version) {
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final cleaned = segment.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isNotEmpty && cleaned.contains('.')) return cleaned;
    return 'MomoPet-$version.msix';
  }
}

/// 比较版本：支持 `v` 前缀、`+build`、`-prerelease`。
bool isNewerVersion(String candidate, String current) => compareVersions(candidate, current) > 0;

int compareVersions(String a, String b) {
  final left = _ParsedVersion.parse(a);
  final right = _ParsedVersion.parse(b);
  if (left == null || right == null) return 0;

  for (var i = 0; i < 3; i++) {
    final diff = left.numbers[i] - right.numbers[i];
    if (diff != 0) return diff.sign;
  }
  final buildDiff = left.build - right.build;
  if (buildDiff != 0) return buildDiff.sign;

  // 1.0.0-beta < 1.0.0
  if (left.pre.isEmpty != right.pre.isEmpty) return left.pre.isEmpty ? 1 : -1;
  return left.pre.compareTo(right.pre).sign;
}

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.build, this.pre);

  final List<int> numbers;
  final int build;
  final String pre;

  static _ParsedVersion? parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

    var build = 0;
    final plus = text.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(text.substring(plus + 1)) ?? 0;
      text = text.substring(0, plus);
    }

    var pre = '';
    final dash = text.indexOf('-');
    if (dash >= 0) {
      pre = text.substring(dash + 1).toLowerCase();
      text = text.substring(0, dash);
    }

    final parts = text.split('.');
    final numbers = <int>[];
    for (var i = 0; i < 3; i++) {
      final value = int.tryParse(i < parts.length ? parts[i] : '0');
      if (value == null) return null;
      numbers.add(value);
    }
    return _ParsedVersion(numbers, build, pre);
  }
}
