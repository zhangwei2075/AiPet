import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/ui/common.dart';
import 'package:momopet/ui/feature_help.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('功能开关说明', () {
    testWidgets('SettingRow 不带 help 时没有 Tooltip 也没有 ⓘ 标记', (tester) async {
      await tester.pumpWidget(_wrap(
        SettingRow(
          title: '桌面散步',
          child: Switch(value: true, onChanged: (_) {}),
        ),
      ));
      expect(find.byType(Tooltip), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
      expect(find.text('桌面散步'), findsOneWidget);
    });

    testWidgets('SettingRow 带 help 时说明放进 richMessage，标题带 ⓘ 标记', (tester) async {
      await tester.pumpWidget(_wrap(
        SettingRow(
          title: '完整本机权限',
          subtitle: '12 / 12 项已授予',
          help: '一次授予 12 项本机能力，关闭后所有工具都会被拦截。',
          child: Switch(value: true, onChanged: (_) {}),
        ),
      ));
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      final text = (tooltip.richMessage! as TextSpan).toPlainText();
      expect(text, contains('完整本机权限'));
      expect(text, contains('一次授予 12 项本机能力'));
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(find.text('12 / 12 项已授予'), findsOneWidget);
    });

    testWidgets('FeatureHelp 悬停后真的能弹出说明', (tester) async {
      const target = Key('hover-target');
      await tester.pumpWidget(_wrap(
        FeatureHelp(
          label: '自主执行',
          description: '目标队列 + 多步规划循环',
          child: const SizedBox(key: target, width: 120, height: 40),
        ),
      ));
      expect(find.textContaining('目标队列 + 多步规划循环'), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byKey(target)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.textContaining('目标队列 + 多步规划循环'), findsOneWidget);
    });

    testWidgets('helpTitle 渲染文字与提示图标', (tester) async {
      await tester.pumpWidget(_wrap(helpTitle('拦截不可逆命令', fontSize: 13)));
      expect(find.text('拦截不可逆命令'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });
  });
}
