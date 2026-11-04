import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'common.dart';
import 'create_tab.dart';
import 'gallery_tab.dart';
import 'panel_chrome.dart';
import 'settings_tab.dart';

class PanelView extends StatelessWidget {
  const PanelView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pet = controller.active;
    final accent = pet?.accent ?? Theme.of(context).colorScheme.primary;
    final content = switch (controller.panelTab) {
      PanelTab.gallery => GalleryTab(controller: controller),
      PanelTab.create => CreateTab(controller: controller),
      PanelTab.settings => SettingsTab(controller: controller),
    };

    if (!controller.isDesktop) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  radius: 24,
                  child: content,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                radius: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    PanelMobileTab(icon: Icons.grid_view_rounded, label: '宠物', selected: controller.panelTab == PanelTab.gallery, accent: accent, onTap: () => controller.setPanelTab(PanelTab.gallery)),
                    PanelMobileTab(icon: Icons.auto_awesome_rounded, label: '生成', selected: controller.panelTab == PanelTab.create, accent: accent, onTap: () => controller.setPanelTab(PanelTab.create)),
                    PanelMobileTab(icon: Icons.tune_rounded, label: '设置', selected: controller.panelTab == PanelTab.settings, accent: accent, onTap: () => controller.setPanelTab(PanelTab.settings)),
                    PanelMobileTab(icon: Icons.close_rounded, label: '桌面', selected: false, accent: accent, onTap: controller.closePanel),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelSidebar(controller: controller, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              radius: 26,
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
