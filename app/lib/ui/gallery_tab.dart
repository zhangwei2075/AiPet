import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../services/petdex_importer.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

class GalleryTab extends StatelessWidget {
  const GalleryTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final pets = controller.pets;
    final activeName = controller.active == null
        ? null
        : controller.displayName(controller.active!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: '我的宠物',
          subtitle: activeName == null
              ? '共 ${pets.length} 只'
              : '共 ${pets.length} 只 · 桌面上是「$activeName」',
          actions: [
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
        _actions(),
        const SizedBox(height: Insets.x4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560
                  ? 3
                  : (constraints.maxWidth >= 360 ? 2 : 1);
              return GridView.builder(
                padding: const EdgeInsets.only(bottom: Insets.x3),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: Insets.x3,
                  mainAxisSpacing: Insets.x3,
                  childAspectRatio: columns == 1 ? 1.5 : 0.86,
                ),
                itemCount: pets.length + 1,
                itemBuilder: (context, index) {
                  if (index == pets.length) {
                    return CreateTile(
                        onTap: () => controller.openPanel(PanelTab.create));
                  }
                  final pet = pets[index];
                  return PetTile(
                    pet: pet,
                    selected: pet.id == controller.active?.id,
                    memoryLine: _memoryLine(controller, pet),
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
                                title:
                                    Text('送走 ${controller.displayName(pet)}？'),
                                content: const Text('宠物包会从本地删除，照片不会被删除。'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('再想想')),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('删除',
                                        style:
                                            TextStyle(color: AppColors.danger)),
                                  ),
                                ],
                              ),
                            );
                            if (!context.mounted) return;
                            if (confirmed == true) {
                              await controller.deletePet(pet);
                            }
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

  /// 快捷动作条：点一下收起面板，回桌面看它表演。
  /// 原来是一排 5 个胶囊按钮，占一整行还不够整齐；改成一条工具条，图标对齐、留白稳定。
  Widget _actions() {
    final items = <_Action>[
      _Action(Icons.directions_walk_rounded, '走一走', () async {
        await controller.closePanel();
        await controller.stroll();
      }),
      _Action(Icons.directions_run_rounded, '跑一圈', () async {
        await controller.closePanel();
        await controller.stroll(run: true);
      }),
      _Action(Icons.weekend_rounded, '躺下求摸', () async {
        await controller.closePanel();
        controller.lieDown();
      }),
      _Action(Icons.auto_awesome_rounded, '逗一下', () async {
        await controller.closePanel();
        controller.triggerProactive();
      }),
      _Action(Icons.refresh_rounded, '转个圈', () async {
        await controller.closePanel();
        controller.doubleTapPet();
      }),
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.x3, vertical: Insets.x2),
      color: AppColors.surfaceAlt,
      border: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline_rounded,
                  size: 15, color: AppColors.inkFaint),
              const SizedBox(width: 6),
              Text('让它表演',
                  style: AppType.meta.copyWith(color: AppColors.inkSoft)),
            ],
          );
          final buttons = [
            for (final item in items)
              _ActionButton(
                icon: item.icon,
                label: item.label,
                onTap: () => item.run(),
              ),
          ];
          if (constraints.maxWidth < 470) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                    padding: const EdgeInsets.only(bottom: Insets.x1),
                    child: label),
                Wrap(
                    spacing: Insets.x1,
                    runSpacing: Insets.x1,
                    children: buttons),
              ],
            );
          }
          return Row(
            children: [
              label,
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: Insets.x3),
                color: AppColors.line,
              ),
              for (final button in buttons) Expanded(child: button),
            ],
          );
        },
      ),
    );
  }
}

/// 卡片上的记忆行只保留两项，塞下「聊过 N 轮」会被截断成省略号。
String _memoryLine(AppController controller, Pet pet) {
  final memory = controller.memory.of(pet.id);
  return '认识 ${memory.daysTogether} 天 · 摸过 ${memory.taps} 次';
}

class _Action {
  const _Action(this.icon, this.label, this.run);

  final IconData icon;
  final String label;
  final Future<void> Function() run;
}

class _ActionButton extends StatefulWidget {
  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon,
                  size: 16, color: _hover ? inkOn(accent) : AppColors.inkSoft),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _hover ? AppColors.ink : AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PetTile extends StatelessWidget {
  const PetTile({
    super.key,
    required this.pet,
    required this.selected,
    this.memoryLine,
    this.nameLabel,
    this.onUse,
    this.onRename,
    this.onDelete,
  });

  final Pet pet;
  final bool selected;
  final String? memoryLine;
  final VoidCallback? onUse;
  final String? nameLabel;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasMenu = onRename != null || onDelete != null;
    return SoftTile(
      selected: selected,
      onTap: onUse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                // 所有卡片共用同一套中性底，宠物的 accent 只出现在标签和选中环上。
                // 原来每张卡一片渐变，四个颜色堆在一起反而看不清宠物。
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFBF8F3), Color(0xFFF4EFE7)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.x4),
                      child: Image(
                          image: pet.imageFor(PetMood.idle),
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  left: Insets.x2,
                  top: Insets.x2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: pet.builtin
                          ? AppColors.surface.withValues(alpha: 0.9)
                          : tintOf(pet.accent, 0.9),
                      borderRadius: BorderRadius.circular(Radii.xs),
                      border: Border.all(
                          color: pet.builtin
                              ? AppColors.line
                              : Colors.transparent),
                    ),
                    child: Text(
                      pet.builtin ? '官方' : '我的',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: pet.builtin
                            ? AppColors.inkSoft
                            : readableOn(pet.accent),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: Insets.x2,
                    top: Insets.x2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(Radii.xs),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 11, color: inkOn(pet.accent)),
                          const SizedBox(width: 3),
                          Text(
                            '使用中',
                            style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: inkOn(pet.accent)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasMenu)
                  Positioned(
                    right: Insets.x1,
                    bottom: Insets.x1,
                    child: _MenuButton(
                        pet: pet, onRename: onRename, onDelete: onDelete),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Insets.x3, Insets.x3 - 2, Insets.x3, Insets.x3 - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameLabel ?? pet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: pet.personality.traits
                      .take(2)
                      .map((trait) =>
                          TagChip(label: trait, color: pet.accent, dense: true))
                      .toList(),
                ),
                if (memoryLine != null && memoryLine!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    memoryLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkFaint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片右下角的「⋯」菜单：重命名 / 送走。
/// 两个小图标常驻太吵，收进菜单后每张卡只需要一个入口。
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.pet, this.onRename, this.onDelete});

  final Pet pet;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      splashRadius: 16,
      iconSize: 16,
      icon: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
        ),
        child: const Icon(Icons.more_horiz_rounded,
            size: 15, color: AppColors.inkSoft),
      ),
      onSelected: (value) {
        if (value == 'rename') onRename?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (context) => [
        if (onRename != null)
          const PopupMenuItem(
            value: 'rename',
            height: 38,
            child: Row(children: [
              Icon(Icons.edit_rounded, size: 15),
              SizedBox(width: 8),
              Text('改个名字')
            ]),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            height: 38,
            child: Row(children: [
              Icon(Icons.delete_outline_rounded,
                  size: 15, color: AppColors.danger),
              SizedBox(width: 8),
              Text('送走它', style: TextStyle(color: AppColors.danger)),
            ]),
          ),
      ],
    );
  }
}

class CreateTile extends StatefulWidget {
  const CreateTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<CreateTile> createState() => _CreateTileState();
}

class _CreateTileState extends State<CreateTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DashedBox(
          color: _hover ? accent : AppColors.line,
          background: _hover
              ? tintOf(accent, 0.05)
              : AppColors.surfaceAlt.withValues(alpha: 0.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: Motion.base,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _hover ? accent : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: _hover ? accent : AppColors.line),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: _hover ? readableOn(accent) : AppColors.inkSoft,
                  size: 20,
                ),
              ),
              const SizedBox(height: Insets.x3),
              const Text('用照片生成',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                '一张照片，一只新宠物',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 对话框
// ---------------------------------------------------------------------------

/// 改名对话框：保存自定义昵称，「恢复默认」清空昵称回到宠物包名字。
Future<void> _showRenameDialog(
    BuildContext context, AppController controller, Pet pet) async {
  final textController =
      TextEditingController(text: controller.displayName(pet));
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('给它起个名字'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: textController,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '输入新名字', counterText: ''),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('恢复默认')),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('保存')),
      ],
    ),
  );
  if (result == null) return;
  final trimmed = result.trim();
  await controller.renamePet(pet.id, trimmed.isEmpty ? null : trimmed);
}

Future<void> _showPetdexImport(
    BuildContext context, AppController controller) async {
  final pets = await controller.scanPetdex();
  if (!context.mounted) return;
  final root = PetdexImporter.defaultRoot();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('导入 Petdex 宠物'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pets.isEmpty
                  ? '没有在 ${root.path} 找到宠物。先运行：npx petdex install boba'
                  : '只导入本机已安装的宠物；素材版权归原作者，请勿随 App 分发。',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.inkSoft, height: 1.55),
            ),
            if (pets.isNotEmpty) ...[
              const SizedBox(height: Insets.x3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final pet = pets[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.pets_rounded, size: 18),
                      title:
                          Text(pet.name, style: const TextStyle(fontSize: 13)),
                      subtitle: pet.description.isEmpty
                          ? null
                          : Text(pet.description,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.add_rounded, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        controller.importPetdex(pet);
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    ),
  );
}
