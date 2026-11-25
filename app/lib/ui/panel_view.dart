import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'common.dart';
import 'create_tab.dart';
import 'gallery_tab.dart';
import 'panel_chrome.dart';
import 'settings_tab.dart';
import 'theme.dart';

class PanelView extends StatelessWidget {
  const PanelView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final accent =
        controller.active?.accent ?? Theme.of(context).colorScheme.primary;
    final content = switch (controller.panelTab) {
      PanelTab.gallery => GalleryTab(controller: controller),
      PanelTab.create => CreateTab(controller: controller),
      PanelTab.settings => SettingsTab(controller: controller),
    };

    if (!controller.isDesktop) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Insets.x2),
          child: Column(
            children: [
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.x4, Insets.x4, Insets.x4, Insets.x3),
                  radius: Radii.panel,
                  child: content,
                ),
              ),
              const SizedBox(height: Insets.x2),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                radius: Radii.panel,
                child: Row(
                  children: [
                    PanelMobileTab(
                      icon: Icons.grid_view_rounded,
                      label: '宠物',
                      selected: controller.panelTab == PanelTab.gallery,
                      accent: accent,
                      onTap: () => controller.setPanelTab(PanelTab.gallery),
                    ),
                    PanelMobileTab(
                      icon: Icons.auto_awesome_rounded,
                      label: '生成',
                      selected: controller.panelTab == PanelTab.create,
                      accent: accent,
                      onTap: () => controller.setPanelTab(PanelTab.create),
                    ),
                    PanelMobileTab(
                      icon: Icons.tune_rounded,
                      label: '设置',
                      selected: controller.panelTab == PanelTab.settings,
                      accent: accent,
                      onTap: () => controller.setPanelTab(PanelTab.settings),
                    ),
                    PanelMobileTab(
                      icon: Icons.close_rounded,
                      label: '桌面',
                      selected: false,
                      accent: accent,
                      onTap: controller.closePanel,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(Insets.x3),
      child: Column(
        children: [
          // 面板模式的拖动把手：宠物模式靠 pet_view 的拖拽手势，
          // 面板模式下那套手势不在，必须给一个明确的抓手。
          MouseRegion(
            cursor: SystemMouseCursors.move,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (_) => controller.beginWindowDrag(),
              child: SizedBox(
                height: 16,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelSidebar(controller: controller, accent: accent),
                const SizedBox(width: Insets.x3),
                Expanded(
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(
                        Insets.x6, Insets.x5, Insets.x6, Insets.x4),
                    radius: Radii.panel,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
