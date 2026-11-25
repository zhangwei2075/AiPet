
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
              label: '逗一下',
              icon: Icons.auto_awesome_rounded,
              filled: false,
              dense: true,
              onPressed: () async {
                await controller.closePanel();
                controller.triggerProactive();
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
                    return CreateTile(onTap: () => controller.openPanel(PanelTab.create));
                  }
                  final pet = pets[index];
                  return PetTile(
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

class PetTile extends StatelessWidget {
  const PetTile({super.key, required this.pet, required this.selected, this.memoryLine, this.nameLabel, this.onUse, this.onRename, this.onDelete});

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

class CreateTile extends StatelessWidget {
  const CreateTile({super.key, required this.onTap});

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
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 照片生成
// ---------------------------------------------------------------------------

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
