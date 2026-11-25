import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

class CreateTab extends StatefulWidget {
  const CreateTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<CreateTab> createState() => CreateTabState();
}

class CreateTabState extends State<CreateTab> {
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

