import 'package:flutter/material.dart';

import '../app_version.dart';
import '../models/pet.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'manage_page.dart';
import 'theme.dart';

/// 手机端的底部标签：图标 + 11px 标签，选中态靠颜色与字重区分。
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
    final color = selected ? inkOn(accent) : AppColors.inkSoft;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.base,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? tintOf(accent, 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面端侧边栏：品牌 → 主导航 → 次级入口。
///
/// 导航不超过 4 项，所以不做折叠菜单；「智能体」原来藏在设置页右上角，
/// 提到这里给个独立入口 —— 它是养宠物之外最重要的能力。
class PanelSidebar extends StatelessWidget {
  const PanelSidebar(
      {super.key, required this.controller, required this.accent});

  final AppController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pet = controller.active;
    return SizedBox(
      width: 208,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        radius: Radii.panel,
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tintOf(accent, 0.16),
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: pet == null
                        ? Icon(Icons.pets_rounded,
                            size: 18, color: inkOn(accent))
                        : ClipOval(
                            child: Image(
                                image: pet.imageFor(PetMood.idle),
                                fit: BoxFit.cover)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('摸摸宠',
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2)),
                        SizedBox(height: 2),
                        Text(
                          'MomoPet',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkFaint,
                              letterSpacing: 0.8,
                              height: 1.2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.x6),
            const Padding(
              padding: EdgeInsets.only(left: 10, bottom: 6),
              child: Text('宠物',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkFaint,
                      letterSpacing: 0.6)),
            ),
            _navItem(Icons.grid_view_rounded, '我的宠物', PanelTab.gallery),
            _navItem(Icons.auto_awesome_rounded, '照片生成', PanelTab.create),
            const SizedBox(height: Insets.x3),
            const Padding(
              padding: EdgeInsets.only(left: 10, bottom: 6),
              child: Text('应用',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkFaint,
                      letterSpacing: 0.6)),
            ),
            _navItem(Icons.tune_rounded, '设置', PanelTab.settings),
            _externalItem(context, Icons.psychology_alt_outlined, '智能体'),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: PillButton(
                label: '回到桌面',
                icon: Icons.arrow_back_rounded,
                filled: false,
                expand: true,
                onPressed: controller.closePanel,
              ),
            ),
            const SizedBox(height: Insets.x2),
            Center(
              child: Text(
                controller.currentVersion.isEmpty
                    ? 'v$kAppVersion'
                    : 'v${controller.currentVersion}',
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkFaint,
                    letterSpacing: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, PanelTab tab) {
    final selected = controller.panelTab == tab;
    return _NavRow(
      icon: icon,
      label: label,
      selected: selected,
      accent: accent,
      onTap: () => controller.setPanelTab(tab),
    );
  }

  Widget _externalItem(BuildContext context, IconData icon, String label) =>
      _NavRow(
        icon: icon,
        label: label,
        selected: false,
        accent: accent,
        trailing: Icons.open_in_new_rounded,
        onTap: () => ManagePage.open(context, controller),
      );
}

class _NavRow extends StatefulWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.selected ? AppColors.ink : AppColors.inkSoft;
    final bg = widget.selected
        ? tintOf(widget.accent, 0.15)
        : (_hover ? AppColors.surfaceAlt : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 17,
                  color: widget.selected
                      ? inkOn(widget.accent)
                      : AppColors.inkSoft,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (widget.trailing != null)
                  Icon(widget.trailing, size: 13, color: AppColors.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
