import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_mode.dart';
import '../pet/pet_view.dart';
import '../state/app_controller.dart';
import 'chat_view.dart';
import 'panel_view.dart';

class PetShell extends StatelessWidget {
  const PetShell({super.key, required this.controller});

  final AppController controller;

  Future<void> _escape() async {
    if (controller.mode == WindowMode.chat) {
      await controller.closeChat();
    } else if (controller.mode == WindowMode.panel) {
      await controller.closePanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: switch (controller.mode) {
              WindowMode.pet => PetView(key: const ValueKey('pet'), controller: controller),
              WindowMode.chat => ChatView(key: const ValueKey('chat'), controller: controller),
              WindowMode.panel => PanelView(key: const ValueKey('panel'), controller: controller),
            },
          ),
        ),
      ),
    );
  }
}
