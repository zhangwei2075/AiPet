import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:momopet/services/update_service.dart';

void main() {
  group('版本比较', () {
    test('基础版本、build 号和 v 前缀', () {
      expect(isNewerVersion('0.2.0', '0.1.0+1'), isTrue);
      expect(isNewerVersion('0.1.0+2', '0.1.0+1'), isTrue);
      expect(isNewerVersion('0.1.0', '0.1.0+1'), isFalse);
      expect(isNewerVersion('v0.2.0', '0.1.9'), isTrue);
      expect(compareVersions('1.0', '1.0.0'), 0);
    });

    test('预发布版本低于正式版，坏版本号不升级', () {
      expect(isNewerVersion('0.2.0-beta', '0.2.0'), isFalse);
      expect(isNewerVersion('0.2.0', '0.2.0-beta'), isTrue);
      expect(isNewerVersion('bad', '0.1.0'), isFalse);
    });
  });

  group('清单解析', () {
    test('支持 windows 分组和扁平字段', () {
      final nested = UpdateInfo.fromJson({
        'version': '0.2.0',
        'notes': '新增多显示器游走',
        'windows': {
          'url': 'https://example.com/MomoPet-0.2.0.msix',
          'sha256': 'ABC',
          'size': 123,
        },
      });
      expect(nested, isNotNull);
      expect(nested!.version, '0.2.0');
      expect(nested.notes, '新增多显示器游走');
      expect(nested.sha256, 'abc');
      expect(nested.size, 123);
      expect(nested.isInstaller, isTrue);

      final flat = UpdateInfo.fromJson({
        'version': 'v0.3.0',
        'url': 'https://example.com/download',
        'notes': 'flat',
      });
      expect(flat, isNotNull);
      expect(flat!.version, 'v0.3.0');
      expect(flat.isInstaller, isFalse);
    });

    test('缺少 version 或 url 返回 null', () {
      expect(UpdateInfo.fromJson(const {'version': '0.2.0'}), isNull);
      expect(UpdateInfo.fromJson(const {'url': 'https://example.com/a.msix'}), isNull);
    });
  });

  group('检查更新', () {
    test('发现新版本', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/update.json');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'version': '0.2.0',
            'windows': {'url': 'https://example.com/MomoPet-0.2.0.msix'},
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = UpdateService(client: client);

      final info = await service.check(
        manifestUrl: 'https://example.com/update.json',
        currentVersion: '0.1.0+1',
      );

      expect(info?.version, '0.2.0');
    });

    test('已是最新版本返回 null', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'version': '0.1.0', 'url': 'https://example.com/a.msix'}),
            200,
          ));
      final service = UpdateService(client: client);

      expect(
        await service.check(
          manifestUrl: 'https://example.com/update.json',
          currentVersion: '0.1.0+1',
        ),
        isNull,
      );
    });

    test('HTTP 错误、坏 JSON、坏地址都会抛出可读异常', () async {
      final badStatus = UpdateService(
        client: MockClient((request) async => http.Response('nope', 500)),
      );
      await expectLater(
        badStatus.check(manifestUrl: 'https://example.com/u.json', currentVersion: '0.1.0'),
        throwsA(isA<UpdateException>()),
      );

      final badJson = UpdateService(
        client: MockClient((request) async => http.Response('not json', 200)),
      );
      await expectLater(
        badJson.check(manifestUrl: 'https://example.com/u.json', currentVersion: '0.1.0'),
        throwsA(isA<UpdateException>()),
      );

      final service = UpdateService(client: MockClient((request) async => http.Response('{}', 200)));
      await expectLater(
        service.check(manifestUrl: 'not-a-url', currentVersion: '0.1.0'),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  group('下载安装包', () {
    test('写入临时文件并校验 sha256', () async {
      final bytes = utf8.encode('fake-installer-bytes');
      final digest = sha256.convert(bytes).toString();
      final client = MockClient((request) async => http.Response.bytes(bytes, 200));
      final service = UpdateService(client: client);
      final directory = await Directory.systemTemp.createTemp('momo-update-');
      addTearDown(() => directory.delete(recursive: true));

      final progress = <int>[];
      final file = await service.download(
        UpdateInfo(
          version: '0.2.0',
          downloadUrl: 'https://example.com/MomoPet-0.2.0.msix',
          sha256: digest,
          size: bytes.length,
        ),
        directory: directory,
        onProgress: (received, total) => progress.add(received),
      );

      expect(file.path, endsWith('MomoPet-0.2.0.msix'));
      expect(await file.readAsBytes(), bytes);
      expect(progress, isNotEmpty);
      expect(progress.last, bytes.length);
    });

    test('sha256 不匹配时删除文件并抛错', () async {
      final bytes = utf8.encode('tampered');
      final client = MockClient((request) async => http.Response.bytes(bytes, 200));
      final service = UpdateService(client: client);
      final directory = await Directory.systemTemp.createTemp('momo-update-');
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}${Platform.pathSeparator}MomoPet-0.2.0.msix');

      await expectLater(
        service.download(
          UpdateInfo(
            version: '0.2.0',
            downloadUrl: 'https://example.com/MomoPet-0.2.0.msix',
            sha256: '0' * 64,
          ),
          directory: directory,
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(await target.exists(), isFalse);
    });

    test('下载地址必须是 http/https', () async {
      final service = UpdateService(client: MockClient((request) async => http.Response('', 200)));
      final directory = await Directory.systemTemp.createTemp('momo-update-');
      addTearDown(() => directory.delete(recursive: true));

      await expectLater(
        service.download(
          const UpdateInfo(version: '0.2.0', downloadUrl: 'file:///C:/a.msix'),
          directory: directory,
        ),
        throwsA(isA<UpdateException>()),
      );
    });
  });
}
