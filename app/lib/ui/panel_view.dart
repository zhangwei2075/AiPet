import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/settings.dart';
import '../services/petdex_importer.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';
class PanelView extends StatelessWidget {
  const PanelView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pet = controller.active;
    final accent = pet?.accent ?? Theme.of(context).colorScheme.primary;
    final content = switch (controller.panelTab) {
      PanelTab.gallery => _GalleryTab(controller: controller),
      PanelTab.create => _CreateTab(controller: controller),
      PanelTab.settings => _SettingsTab(controller: controller),
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
                    _MobileTab(icon: Icons.grid_view_rounded, label: '宠物', selected: controller.panelTab == PanelTab.gallery, accent: accent, onTap: () => controller.setPanelTab(PanelTab.gallery)),
                    _MobileTab(icon: Icons.auto_awesome_rounded, label: '生成', selected: controller.panelTab == PanelTab.create, accent: accent, onTap: () => controller.setPanelTab(PanelTab.create)),
                    _MobileTab(icon: Icons.tune_rounded, label: '设置', selected: controller.panelTab == PanelTab.settings, accent: accent, onTap: () => controller.setPanelTab(PanelTab.settings)),
                    _MobileTab(icon: Icons.close_rounded, label: '桌面', selected: false, accent: accent, onTap: controller.closePanel),
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
          _Sidebar(controller: controller, accent: accent),
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

class _MobileTab extends StatelessWidget {
  const _MobileTab({
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller, required this.accent});

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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tips_and_updates_rounded, size: 13, color: accent),
                      const SizedBox(width: 5),
                      const Text('小提示', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '按住宠物可以拖到任意位置；双击会转圈；桌面空白处可穿透鼠标。',
                    style: TextStyle(fontSize: 10.5, height: 1.45, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
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

class _GalleryTab extends StatelessWidget {
  const _GalleryTab({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pets = controller.pets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          alignment: WrapAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的宠物', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('每一只都住在你的桌面上，可以随时切换', style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                PillButton(
                  label: '导入 Petdex',
                  icon: Icons.pets_rounded,
                  filled: false,
                  onPressed: () => _showPetdexImport(context, controller),
                ),
                PillButton(
                  label: '用照片生成',
                  icon: Icons.add_a_photo_rounded,
                  onPressed: () => controller.openPanel(PanelTab.create),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 快捷动作：点一下回到桌面上看宠物表演
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillButton(
              label: '走一走',
              icon: Icons.directions_walk_rounded,
              filled: false,
              dense: true,
              onPressed: () async {
                await controller.closePanel();
                await controller.stroll();
              },
            ),
            PillButton(
              label: '跑一圈',
              icon: Icons.directions_run_rounded,
              filled: false,
              dense: true,
              onPressed: () async {
                await controller.closePanel();
                await controller.stroll(run: true);
              },
            ),
            PillButton(
              label: '躺下求摸',
              icon: Icons.favorite_rounded,
              filled: false,
              dense: true,
              onPressed: () async {
                await controller.closePanel();
                controller.lieDown();
              },
            ),
            PillButton(
              label: '转个圈',
              icon: Icons.refresh_rounded,
              filled: false,
              dense: true,
              onPressed: () async {
                await controller.closePanel();
                controller.doubleTapPet();
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 480 ? 2 : 3;
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns == 2 ? 0.78 : 0.72,
                ),
                itemCount: pets.length + 1,
                itemBuilder: (context, index) {
                  if (index == pets.length) {
                    return _CreateTile(onTap: () => controller.openPanel(PanelTab.create));
                  }
                  final pet = pets[index];
                  return _PetTile(
                    pet: pet,
                    selected: pet.id == controller.active?.id,
                    memoryLine: controller.memory.of(pet.id).shortLine,
                    nameLabel: controller.displayName(pet),
                    onRename: () => _showRenameDialog(context, controller, pet),
                    onUse: () async {
                      await controller.selectPet(pet);
                      await controller.closePanel();
                    },
                    onDelete: pet.builtin
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: AppColors.card,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                title: Text('送走 ${controller.displayName(pet)}?', style: const TextStyle(fontSize: 16)),
                                content: const Text('宠物包会从本地删除，照片不会被删除。', style: TextStyle(fontSize: 12.5)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('再想想')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('删除', style: TextStyle(color: AppColors.danger)),
                                  ),
                                ],
                              ),
                            );
                            if (!context.mounted) return;
                            if (confirmed == true) await controller.deletePet(pet);
                          },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PetTile extends StatelessWidget {
  const _PetTile({required this.pet, required this.selected, this.memoryLine, this.nameLabel, this.onUse, this.onRename, this.onDelete});

  final Pet pet;
  final bool selected;
  final String? memoryLine;
  final VoidCallback? onUse;
  final String? nameLabel;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return SoftTile(
      selected: selected,
      onTap: onUse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    pet.accent.withValues(alpha: 0.18),
                    pet.accent.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Image(
                      image: pet.imageFor(PetMood.idle),
                      width: 128,
                      height: 128,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: TagChip(label: pet.builtin ? '官方' : '我的', color: pet.accent, dense: true),
                  ),
                  if (selected)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: pet.accent, borderRadius: BorderRadius.circular(999)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 10, color: Colors.white),
                            SizedBox(width: 2),
                            Text('使用中', style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nameLabel ?? pet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (onRename != null)
                      InkWell(
                        onTap: onRename,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.edit_rounded, size: 14, color: AppColors.inkSoft),
                        ),
                      ),
                    if (onDelete != null)
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.inkSoft),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: pet.personality.traits
                      .take(2)
                      .map((trait) => TagChip(label: trait, color: pet.accent, dense: true))
                      .toList(),
                ),
                const SizedBox(height: 4),
                if (memoryLine != null && memoryLine!.isNotEmpty)
                  Text(
                    memoryLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.inkSoft),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(Icons.add_photo_alternate_outlined, color: accent, size: 22),
            ),
            const SizedBox(height: 12),
            const Text('用照片生成', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              '上传一张照片\n领养专属宠物',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 照片生成
// ---------------------------------------------------------------------------

class _CreateTab extends StatefulWidget {
  const _CreateTab({required this.controller});

  final AppController controller;

  @override
  State<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends State<_CreateTab> {
  final TextEditingController _name = TextEditingController();
  String _style = 'sticker';
  bool _picking = false;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      // file_picker 12+ 起 FilePicker.pickFiles 直接返回 List<PlatformFile>，
      // 且不再有 withData 开关，需要自己把字节读出来。
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('读取不到图片内容，换一张试试')));
        return;
      }
      controller.loadSource(bytes, file.name);
      _name.text = '';
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败：$error')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('照片生成宠物', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('一张照片 → 抠图贴纸 → 自动配色与性格', style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
            const Spacer(),
            if (controller.sourceBytes != null && preview == null)
              PillButton(
                label: controller.generating ? '生成中…' : '重新选择',
                icon: Icons.refresh_rounded,
                dense: true,
                filled: false,
                onPressed: controller.generating ? null : _pick,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: preview != null
              ? _resultView(preview)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 620) {
                      return Column(
                        children: [
                          SizedBox(height: 220, child: _sourceCard()),
                          const SizedBox(height: 14),
                          Expanded(child: _formCard()),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _sourceCard()),
                        const SizedBox(width: 18),
                        Expanded(flex: 6, child: _formCard()),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _sourceCard() {
    final bytes = controller.sourceBytes;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? InkWell(
              onTap: _picking ? null : _pick,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_picking)
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  else
                    Icon(Icons.cloud_upload_outlined, size: 42, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 14),
                  const Text('点击选择照片', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22),
                    child: Text(
                      '建议：主体清晰、背景干净的半身照 / 宠物照\n支持 JPG / PNG / WebP，最大 15MB',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.5),
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                Positioned(
                  left: 10,
                  top: 10,
                  child: PillButton(label: '换一张', dense: true, filled: false, icon: Icons.swap_horiz_rounded, onPressed: _picking ? null : _pick),
                ),
              ],
            ),
    );
  }

  Widget _formCard() {
    final accent = Theme.of(context).colorScheme.primary;
    final hasSource = controller.sourceBytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _steps(),
                const SizedBox(height: 18),
                const SectionLabel('名字（可留空，自动取名）'),
                TextField(
                  controller: _name,
                  enabled: hasSource && !controller.generating,
                  decoration: const InputDecoration(hintText: '比如：小橘'),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                const SectionLabel('贴纸风格'),
                Wrap(
                  spacing: 8,
                  children: [
                    _styleChip('sticker', '白边贴纸', '推荐'),
                    _styleChip('soft', '柔光', '更接近原图'),
                    _styleChip('original', '原图', '不调色'),
                  ],
                ),
                const SizedBox(height: 18),
                _forgeStatus(),
                if (controller.generating) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: controller.generationProgress,
                      minHeight: 6,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(controller.generationStage, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                ],
                if (controller.generationError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.generationError!,
                    style: const TextStyle(fontSize: 11, color: AppColors.danger, height: 1.45),
                  ),
                ],
                if (controller.generationNotice != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    controller.generationNotice!,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9A6A1E), height: 1.45),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: controller.generating ? '正在生成…' : '开始生成',
                icon: Icons.auto_awesome_rounded,
                enabled: hasSource && !controller.generating,
                onPressed: () => controller.generate(style: _style, name: _name.text),
              ),
            ),
            if (controller.sourceBytes != null) ...[
              const SizedBox(width: 8),
              PillButton(
                label: '清除',
                filled: false,
                dense: true,
                onPressed: controller.generating ? null : controller.resetGeneration,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _styleChip(String value, String label, String hint) {
    final selected = _style == value;
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _style = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? accent : AppColors.line, width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.ink : AppColors.inkSoft),
            ),
            const SizedBox(height: 1),
            Text(hint, style: const TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }

  Widget _steps() {
    final done = controller.preview != null;
    final stage = controller.generating
        ? (controller.generationProgress < 0.3 ? 0 : (controller.generationProgress < 0.8 ? 1 : 2))
        : (done ? 3 : (controller.sourceBytes != null ? 0 : -1));
    const labels = ['照片', '抠图', '性格', '领养'];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index <= stage;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: active ? Theme.of(context).colorScheme.primary : AppColors.line,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  active ? Icons.check_rounded : Icons.circle,
                  size: active ? 11 : 6,
                  color: active ? Colors.white : AppColors.inkSoft,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 10.5,
                  color: active ? AppColors.ink : AppColors.inkSoft,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (index != labels.length - 1) const Spacer(),
            ],
          ),
        );
      }),
    );
  }

  Widget _forgeStatus() {
    final online = controller.forgeOnline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: online ? const Color(0xFFEAF7EF) : const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            online ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 13,
            color: online ? const Color(0xFF3D9A5F) : const Color(0xFFB57B2A),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              online
                  ? 'PetForge 已连接 · ${controller.settings.forgeUrl}'
                  : '形象工坊未连接，将使用本地徽章模式（也能生成，但抠图更简单）',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: online ? const Color(0xFF2F7A4B) : const Color(0xFF8A5D1E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultView(GeneratedPet result) {
    final accent = Theme.of(context).colorScheme.primary;
    final pack = result.pack;
    final name = pack['name']?.toString() ?? '新朋友';
    final traits = ((pack['personality'] as Map?)?['traits'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final image = result.images['base'];

    final artwork = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.2), Colors.white.withValues(alpha: 0.5)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Stack(
        children: [
          Center(
            child: image == null
                ? const SizedBox()
                : Image.memory(image, width: 260, height: 260, fit: BoxFit.contain),
          ),
          const Positioned(
            left: 12,
            top: 12,
            child: TagChip(label: '刚刚出生', color: Color(0xFF57B87A)),
          ),
        ],
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('它睁开眼睛了', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: traits.map((trait) => TagChip(label: trait, color: accent)).toList(),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
          child: Text(
            ((pack['personality'] as Map?)?['greeting']?.toString()) ?? '请多关照！',
            style: const TextStyle(fontSize: 12, height: 1.55),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '抠图方式：${(((pack['metrics'] as Map?)?['cutout']) ?? 'unknown')}'
          ' · 耗时 ${result.elapsedMs}ms',
          style: const TextStyle(fontSize: 10, color: AppColors.inkSoft),
        ),
        if (controller.generationNotice != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.generationNotice!,
            style: const TextStyle(fontSize: 10.5, height: 1.45, color: Color(0xFF9A6A1E)),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: '收养它',
                icon: Icons.favorite_rounded,
                onPressed: () => controller.adoptPreview(name: _name.text),
              ),
            ),
            const SizedBox(width: 8),
            PillButton(
              label: '重新生成',
              filled: false,
              dense: true,
              onPressed: controller.generating
                  ? null
                  : () => controller.generate(style: _style, name: _name.text),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: controller.resetGeneration,
          child: const Text('换一张照片', style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 240, child: artwork),
                const SizedBox(height: 14),
                details,
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: artwork),
            const SizedBox(width: 20),
            Expanded(flex: 5, child: SingleChildScrollView(child: details)),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 设置
// ---------------------------------------------------------------------------

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.controller});

  final AppController controller;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _forgeUrl;
  late final TextEditingController _updateUrl;
  Timer? _debounce;
  late double _scale;

  AppController get controller => widget.controller;
  AppSettings get settings => controller.settings;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: settings.baseUrl);
    _model = TextEditingController(text: settings.model);
    _apiKey = TextEditingController(text: settings.apiKey);
    _forgeUrl = TextEditingController(text: settings.forgeUrl);
    _updateUrl = TextEditingController(text: settings.updateManifestUrl);
    _scale = settings.scale;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _forgeUrl.dispose();
    _updateUrl.dispose();
    super.dispose();
  }

  void _commit(AppSettings next, {bool immediate = false}) {
    if (immediate) {
      controller.updateSettings(next);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), () => controller.updateSettings(next));
  }

  void _applyPreset(String url, String model) {
    _baseUrl.text = url;
    _model.text = model;
    _commit(settings.copyWith(baseUrl: url, model: model, chatBackend: ChatBackendKind.openai), immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('设置', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        const Text('外观、对话模型和形象工坊', style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('外观与行为'),
                _card(
                  Column(
                    children: [
                      SettingRow(
                        title: '宠物大小',
                        subtitle: '当前 ${(_scale * 100).round()}%',
                        child: SizedBox(
                          width: 190,
                          child: Slider(
                            value: _scale,
                            min: 0.15,
                            max: 1.5,
                            divisions: 27,
                            onChanged: (value) => setState(() => _scale = value),
                            onChangeEnd: (value) => _commit(settings.copyWith(scale: value), immediate: true),
                          ),
                        ),
                      ),
                      const Divider(),
                      SettingRow(
                        title: '始终置顶',
                        subtitle: '宠物一直浮在其他窗口上方',
                        child: Switch(
                          value: settings.alwaysOnTop,
                          onChanged: (value) => _commit(settings.copyWith(alwaysOnTop: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '鼠标穿透',
                        subtitle: '宠物以外的透明区域不挡住鼠标点击',
                        child: Switch(
                          value: settings.clickThrough,
                          onChanged: (value) => _commit(settings.copyWith(clickThrough: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '桌面散步',
                        subtitle: '空闲时在桌面上走一小段',
                        child: Switch(
                          value: settings.wander,
                          onChanged: (value) => _commit(settings.copyWith(wander: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '自动睡觉',
                        subtitle: '90 秒没有互动就打个盹',
                        child: Switch(
                          value: settings.autoSleep,
                          onChanged: (value) => _commit(settings.copyWith(autoSleep: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '朗读回复',
                        subtitle: '用系统语音把宠物的话念出来',
                        child: Switch(
                          value: settings.tts,
                          onChanged: (value) => _commit(settings.copyWith(tts: value), immediate: true),
                        ),
                      ),
                      if (controller.isMobile)
                        SettingRow(
                          title: '桌面悬浮窗',
                          subtitle: Platform.isAndroid
                              ? '需要「显示在其他应用上层」权限；关闭 App 后仍会显示'
                              : 'iOS 系统限制，无法浮在其它 App 上方',
                          child: Switch(
                            value: controller.overlayActive,
                            onChanged: Platform.isAndroid ? (_) => controller.toggleMobileOverlay() : null,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('对话'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<ChatBackendKind>(
                              segments: const [
                                ButtonSegment(value: ChatBackendKind.local, label: Text('本地小脑', style: TextStyle(fontSize: 12)), icon: Icon(Icons.offline_bolt_rounded, size: 15)),
                                ButtonSegment(value: ChatBackendKind.openai, label: Text('在线模型', style: TextStyle(fontSize: 12)), icon: Icon(Icons.cloud_rounded, size: 15)),
                              ],
                              selected: {settings.chatBackend},
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: WidgetStateProperty.resolveWith(
                                  (states) => states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.14) : Colors.transparent,
                                ),
                              ),
                              onSelectionChanged: (value) => _commit(
                                settings.copyWith(chatBackend: value.first),
                                immediate: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '本地小脑完全离线；在线模型支持任意 OpenAI 兼容接口（OpenAI / DeepSeek / Ollama / LM Studio）。',
                        style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.5),
                      ),
                      if (settings.chatBackend == ChatBackendKind.openai) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 6,
                          children: [
                            PillButton(label: 'Ollama', dense: true, filled: false, onPressed: () => _applyPreset('http://127.0.0.1:11434/v1', 'qwen2.5:3b')),
                            PillButton(label: 'DeepSeek', dense: true, filled: false, onPressed: () => _applyPreset('https://api.deepseek.com/v1', 'deepseek-chat')),
                            PillButton(label: 'OpenAI', dense: true, filled: false, onPressed: () => _applyPreset('https://api.openai.com/v1', 'gpt-4o-mini')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field('API 地址', _baseUrl, (value) => _commit(settings.copyWith(baseUrl: value.trim()))),
                        const SizedBox(height: 10),
                        _field('模型名', _model, (value) => _commit(settings.copyWith(model: value.trim()))),
                        const SizedBox(height: 10),
                        _field(
                          'API Key（本地模型可留空）',
                          _apiKey,
                          (value) => _commit(settings.copyWith(apiKey: value.trim())),
                          obscure: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('形象工坊 PetForge'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: controller.forgeOnline ? const Color(0xFF57B87A) : const Color(0xFFE0A83C),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            controller.forgeOnline ? '已连接' : '未连接（仍可用本地徽章模式）',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          PillButton(
                            label: '测试连接',
                            dense: true,
                            filled: false,
                            onPressed: () async {
                              await controller.updateSettings(settings.copyWith(forgeUrl: _forgeUrl.text.trim()));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(controller.forgeOnline ? '形象工坊在线，抠图质量最佳' : '连不上，请先启动 Python 服务'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _field('服务地址', _forgeUrl, (value) => _commit(settings.copyWith(forgeUrl: value.trim()))),
                      const SizedBox(height: 8),
                      const Text(
                        '启动方式：进入 services/petforge，执行\npython -m pip install -r requirements.txt\npython -m petforge',
                        style: TextStyle(fontSize: 10, height: 1.6, color: AppColors.inkSoft, fontFamily: 'Consolas'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('更新'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '当前版本 v${controller.currentVersion.isEmpty ? '0.1.0' : controller.currentVersion}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          PillButton(
                            label: controller.checkingUpdate ? '检查中…' : '检查更新',
                            dense: true,
                            filled: false,
                            enabled: !controller.checkingUpdate,
                            onPressed: controller.checkForUpdates,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _field(
                        '版本检查地址（JSON，留空关闭）',
                        _updateUrl,
                        (value) => _commit(settings.copyWith(updateManifestUrl: value.trim())),
                      ),
                      SettingRow(
                        title: '启动时检查更新',
                        subtitle: '需要先填写检查地址',
                        child: Switch(
                          value: settings.autoCheckUpdates,
                          onChanged: (value) => _commit(
                            settings.copyWith(autoCheckUpdates: value),
                            immediate: true,
                          ),
                        ),
                      ),
                      if (controller.updateStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            controller.updateStatus!,
                            style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                          ),
                        ),
                      if (controller.updateError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            controller.updateError!,
                            style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                          ),
                        ),
                      if (controller.availableUpdate != null) ...[
                        if (controller.availableUpdate!.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              controller.availableUpdate!.notes,
                              style: const TextStyle(fontSize: 11, height: 1.5),
                            ),
                          ),
                        if (controller.downloadingUpdate) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: controller.updateProgress > 0 ? controller.updateProgress : null,
                          ),
                        ],
                        const SizedBox(height: 10),
                        PillButton(
                          label: controller.downloadingUpdate
                              ? '下载中…'
                              : (controller.availableUpdate!.isInstaller ? '下载并安装' : '打开下载页'),
                          dense: true,
                          enabled: !controller.downloadingUpdate,
                          onPressed: controller.downloadAndInstallUpdate,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('数据'),
                _card(
                  SettingRow(
                    title: '清空对话记录',
                    subtitle: '只删除聊天内容，宠物形象保留',
                    child: PillButton(
                      label: '清空',
                      dense: true,
                      filled: false,
                      onPressed: () {
                        controller.clearChat();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对话已清空')));
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '摸摸宠 MomoPet v${controller.currentVersion.isEmpty ? '0.1.0' : controller.currentVersion} · Flutter · 参考 VPet / Shimeji / Live2D 的设计',
                    style: const TextStyle(fontSize: 9.5, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
      ),
      child: child,
    );
  }

  Widget _field(String label, TextEditingController controller, ValueChanged<String> onChanged, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(fontSize: 12),
          onChanged: onChanged,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }
}

/// 改名对话框：保存自定义昵称，「恢复默认」清空昵称回到宠物包名字。
Future<void> _showRenameDialog(BuildContext context, AppController controller, Pet pet) async {
  final textController = TextEditingController(text: controller.displayName(pet));
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('给它起个名字', style: TextStyle(fontSize: 16)),
      content: TextField(
        controller: textController,
        autofocus: true,
        maxLength: 12,
        decoration: const InputDecoration(hintText: '输入新名字', counterText: ''),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('恢复默认'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(context, textController.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (result == null) return;
  final trimmed = result.trim();
  await controller.renamePet(pet.id, trimmed.isEmpty ? null : trimmed);
}

Future<void> _showPetdexImport(BuildContext context, AppController controller) async {
  final pets = await controller.scanPetdex();
  if (!context.mounted) return;
  final root = PetdexImporter.defaultRoot();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('导入 Petdex 宠物', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pets.isEmpty
                  ? '没有在 ${root.path} 找到宠物。\n\n先运行：\nnpx petdex install boba'
                  : '只导入本机已安装的宠物；素材版权归原作者，请勿随 App 分发。',
              style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5),
            ),
            if (pets.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final pet in pets)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.pets_rounded),
                        title: Text(pet.name),
                        subtitle: pet.description.isEmpty
                            ? null
                            : Text(
                                pet.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () {
                          Navigator.pop(context);
                          controller.importPetdex(pet);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    ),
  );
}
