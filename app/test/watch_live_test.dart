import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/agent/watch.dart';

/// 真实联网冒烟：默认跳过，需要时用
/// `WATCH_LIVE=1 flutter test test/watch_live_test.dart` 打开。
void main() {
  final live = Platform.environment['WATCH_LIVE'] == '1';
  test('真实抓取财联社电报', () async {
    final items = await WatchFetcher().fetch(WatchSourceKind.cailianshe, count: 5);
    expect(items, isNotEmpty, reason: '接口无返回，检查签名或网络');
    expect(items.first.title, isNotEmpty);
    // ignore: avoid_print
    print('LIVE 抓到 ${items.length} 条，首条：${items.first.title}');
  }, skip: live ? false : '联网冒烟，需 WATCH_LIVE=1');
}
