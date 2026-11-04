import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile/overlay_pet.dart';
import 'state/app_controller.dart';
import 'ui/pet_shell.dart';
import 'ui/theme.dart';

/// Android 悬浮窗入口（flutter_overlay_window 要求顶层函数）。
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const OverlayPet());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final controller = AppController();
  try {
    await controller.initialize();
  } catch (error, stack) {
    debugPrint('初始化失败: $error\n$stack');
  }
  runApp(MomoPetApp(controller: controller));
}

class MomoPetApp extends StatelessWidget {
  const MomoPetApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final accent = controller.active?.accent ?? const Color(0xFFF0A35E);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '摸摸宠 MomoPet',
          color: Colors.transparent,
          theme: buildAppTheme(accent),
          home: PetShell(controller: controller),
        );
      },
    );
  }
}
