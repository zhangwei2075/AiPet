
import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

class PanelMobileTab extends StatelessWidget {
  const PanelMobileTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: selected ? accent : AppColors.inkSoft),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.ink : AppColors.inkSoft,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PanelSidebar extends StatelessWidget {
  const PanelSidebar({super.key, required this.controller, required this.accent});

  final AppController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pet = controller.active;
    return SizedBox(
      width: 204,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        radius: 26,
        color: const Color(0xFFFFFDF9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.15),
                  ),
                  child: pet == null
                      ? Icon(Icons.pets_rounded, size: 20, color: accent)
                      : ClipOval(child: Image(image: pet.imageFor(PetMood.idle), fit: BoxFit.cover)),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('摸摸宠', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      Text('MomoPet', style: TextStyle(fontSize: 10, color: AppColors.inkSoft, letterSpacing: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _navItem(Icons.grid_view_rounded, '我的宠物', PanelTab.gallery),
            _navItem(Icons.auto_awesome_rounded, '照片生成', PanelTab.create),
            _navItem(Icons.tune_rounded, '设置', PanelTab.settings),
            const Spacer(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: '回到桌面',
                icon: Icons.arrow_back_rounded,
                onPressed: controller.closePanel,
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text('v0.1.0', style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, PanelTab tab) {
    final selected = controller.panelTab == tab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => controller.setPanelTab(tab),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 17, color: selected ? accent : AppColors.inkSoft),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.ink : AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 我的宠物
// ---------------------------------------------------------------------------

