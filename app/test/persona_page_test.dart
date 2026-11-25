import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/state/app_controller.dart';
import 'package:momopet/ui/persona_page.dart';
import 'package:momopet/ui/settings_tab.dart';
import 'package:momopet/ui/theme.dart';

/// 人设页要有最基本的可用性与版面保证：
/// 三段都在、能加性格标签、900×680 的面板尺寸下不溢出。
/// 保存走磁盘写入（path_provider），这里不点保存，避免把测试绑到宿主环境。
void main() {
  const persona = PetPersonality(
    traits: ['元气', '黏人'],
    tone: '短句、可爱',
    greeting: '嗨，我是小黄豆！',
    catchphrase: '陪你待一会儿～',
    systemPrompt: '你是一只小黄豆，说话简短。',
  );

  const pet = Pet(
    id: 'doudou',
    name: '小黄豆',
    personality: persona,
    palette: [Color(0xFFF0A35E)],
    accent: Color(0xFFF0A35E),
    anchors: PetAnchors(),
    frames: {PetMood.idle: 'idle.png'},
    builtin: true,
    heightRatio: 0.8,
    cutout: 'drawn',
    assetRoot: 'assets/pets/doudou',
  );

  testWidgets('人设页在面板尺寸下渲染完整且不溢出', (tester) async {
    tester.view.physicalSize = const Size(900, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(const Color(0xFFF0A35E)),
      home: PersonaPage(controller: controller, pet: pet),
    ));
    await tester.pump();

    expect(find.text('人设'), findsOneWidget);
    expect(find.text('身份'), findsOneWidget);
    expect(find.text('性格'), findsOneWidget);
    // 宠物包自带的招呼语要出现在输入框里
    expect(find.text(persona.greeting), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 下半部分在 ListView 里，滚下去再断言（懒加载不渲染屏幕外的分组）
    await tester.scrollUntilVisible(find.text('保存人设'), 260,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('说话风格'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('设置页有人设分组且不溢出', (tester) async {
    tester.view.physicalSize = const Size(900, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = AppController();
    controller.pets = const [pet];
    controller.active = pet;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(const Color(0xFFF0A35E)),
      home: Scaffold(
        backgroundColor: AppColors.canvas,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SettingsTab(controller: controller),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('宠物人设'), findsOneWidget);
    expect(find.text('编辑人设'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('可以加一个性格标签', (tester) async {
    tester.view.physicalSize = const Size(900, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(const Color(0xFFF0A35E)),
      home: PersonaPage(controller: controller, pet: pet),
    ));
    await tester.pump();

    // 第 4 个输入框是「加一个性格」；用回车提交，省掉按钮命中的问题
    await tester.enterText(find.byType(TextField).at(3), '话痨');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('话痨'), findsOneWidget);

    controller.dispose();
  });
}
