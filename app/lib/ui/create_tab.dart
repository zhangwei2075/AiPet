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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取不到图片内容，换一张试试')));
        return;
      }
      controller.loadSource(bytes, file.name);
      _name.text = '';
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('选择图片失败：$error')));
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
        AppPageHeader(
          title: '照片生成',
          subtitle: '一张照片，抠成贴纸，再推导性格和名字',
          actions: [
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
        _stepper(),
        const SizedBox(height: Insets.x4),
        Expanded(
          child: preview != null
              ? _resultView(preview)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 560) {
                      return Column(
                        children: [
                          SizedBox(height: 200, child: _sourceCard()),
                          const SizedBox(height: Insets.x3),
                          Expanded(child: _formCard()),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _sourceCard()),
                        const SizedBox(width: Insets.x5),
                        Expanded(flex: 6, child: _formCard()),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 四步进度：照片 → 抠图 → 性格 → 领养。
  Widget _stepper() {
    final accent = Theme.of(context).colorScheme.primary;
    final done = controller.preview != null;
    final stage = controller.generating
        ? (controller.generationProgress < 0.3
            ? 1
            : (controller.generationProgress < 0.8 ? 2 : 3))
        : (done ? 4 : (controller.sourceBytes != null ? 1 : 0));
    const labels = ['照片', '抠图', '性格', '领养'];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0)
            Expanded(
              child: AnimatedContainer(
                duration: Motion.base,
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: index < stage
                    ? accent.withValues(alpha: 0.5)
                    : AppColors.line,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.base,
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: index < stage ? accent : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: index < stage
                        ? accent
                        : (index == stage
                            ? accent.withValues(alpha: 0.6)
                            : AppColors.line),
                    width: index == stage ? 1.6 : 1,
                  ),
                ),
                child: Icon(
                  index < stage ? Icons.check_rounded : Icons.circle,
                  size: index < stage ? 12 : 5,
                  color: index < stage
                      ? readableOn(accent)
                      : (index == stage ? accent : AppColors.line),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 12,
                  color: index <= stage ? AppColors.ink : AppColors.inkFaint,
                  fontWeight:
                      index <= stage ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sourceCard() {
    final bytes = controller.sourceBytes;
    final accent = Theme.of(context).colorScheme.primary;
    if (bytes == null) {
      return SizedBox(
        width: double.infinity,
        child: _HoverDropZone(
          onTap: _picking ? null : _pick,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_picking)
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2))
              else
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: tintOf(accent, 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.add_photo_alternate_outlined,
                      size: 22, color: inkOn(accent)),
                ),
              const SizedBox(height: Insets.x3),
              const Text('选一张照片',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              const Text(
                '正脸、背景干净的照片效果最好',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(Insets.x3),
              child: Image.memory(bytes,
                  fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
            Positioned(
              left: Insets.x2,
              top: Insets.x2,
              child: PillButton(
                label: '换一张',
                dense: true,
                filled: false,
                icon: Icons.swap_horiz_rounded,
                onPressed: _picking ? null : _pick,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formCard() {
    final hasSource = controller.sourceBytes != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppField(
                  label: '名字',
                  hint: '留空会按照片的颜色自动取名',
                  child: TextField(
                    controller: _name,
                    enabled: hasSource && !controller.generating,
                    decoration: const InputDecoration(hintText: '比如：小橘'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: Insets.x4),
                const Text(
                  '贴纸风格',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkSoft),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _styleCard('sticker', '白边贴纸', '推荐')),
                    const SizedBox(width: Insets.x2),
                    Expanded(child: _styleCard('soft', '柔光', '更接近原图')),
                    const SizedBox(width: Insets.x2),
                    Expanded(child: _styleCard('original', '原图', '不调色')),
                  ],
                ),
                const SizedBox(height: Insets.x4),
                AppBanner(
                  tone: controller.forgeOnline
                      ? BannerTone.success
                      : BannerTone.warning,
                  text: controller.forgeOnline
                      ? '形象工坊已连接 · ${controller.settings.forgeUrl}'
                      : '形象工坊未连接，将使用本地徽章模式（也能生成，抠图更简单）',
                ),
                if (controller.generating) ...[
                  const SizedBox(height: Insets.x3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                        value: controller.generationProgress),
                  ),
                  const SizedBox(height: 6),
                  Text(controller.generationStage,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.inkSoft)),
                ],
                if (controller.generationError != null) ...[
                  const SizedBox(height: Insets.x3),
                  AppBanner(
                      tone: BannerTone.danger,
                      text: controller.generationError!),
                ],
                if (controller.generationNotice != null) ...[
                  const SizedBox(height: Insets.x3),
                  AppBanner(
                      tone: BannerTone.warning,
                      text: controller.generationNotice!),
                ],
                const SizedBox(height: Insets.x5),
                const _Tips(),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.x3),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: controller.generating ? '正在生成…' : '开始生成',
                icon: Icons.auto_awesome_rounded,
                enabled: hasSource && !controller.generating,
                expand: true,
                onPressed: () =>
                    controller.generate(style: _style, name: _name.text),
              ),
            ),
            if (controller.sourceBytes != null) ...[
              const SizedBox(width: Insets.x2),
              PillButton(
                label: '清除',
                filled: false,
                dense: true,
                onPressed:
                    controller.generating ? null : controller.resetGeneration,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _styleCard(String value, String label, String hint) {
    final selected = _style == value;
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => setState(() => _style = value),
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? tintOf(accent, 0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(
              color: selected ? accent : AppColors.line,
              width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded,
                      size: 14, color: inkOn(accent)),
              ],
            ),
            const SizedBox(height: 2),
            Text(hint,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.inkFaint)),
          ],
        ),
      ),
    );
  }

  Widget _resultView(GeneratedPet result) {
    final accent = Theme.of(context).colorScheme.primary;
    final pack = result.pack;
    final name = pack['name']?.toString() ?? '新朋友';
    final traits = ((pack['personality'] as Map?)?['traits'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final greeting =
        (pack['personality'] as Map?)?['greeting']?.toString() ?? '请多关照！';
    final image = result.images['base'];

    final artwork = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF8F3), Color(0xFFF2ECE3)],
        ),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(Insets.x4),
              child: image == null
                  ? const SizedBox()
                  : Image.memory(image, fit: BoxFit.contain),
            ),
          ),
          const Positioned(
            left: Insets.x3,
            top: Insets.x3,
            child: TagChip(
                label: '刚刚出生',
                color: AppColors.success,
                icon: Icons.favorite_rounded),
          ),
        ],
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('它睁开眼睛了',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
        const SizedBox(height: 2),
        Text(name, style: AppType.displayColor),
        const SizedBox(height: Insets.x3),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: traits
              .map((trait) => TagChip(label: trait, color: accent))
              .toList(),
        ),
        const SizedBox(height: Insets.x3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Insets.x3),
          decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.control)),
          child:
              Text(greeting, style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
        const SizedBox(height: Insets.x2),
        Text(
          '抠图方式：${(((pack['metrics'] as Map?)?['cutout']) ?? 'unknown')} · 耗时 ${result.elapsedMs}ms',
          style: const TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
        ),
        if (controller.generationNotice != null) ...[
          const SizedBox(height: Insets.x2),
          Text(
            controller.generationNotice!,
            style: const TextStyle(
                fontSize: 11.5, height: 1.5, color: AppColors.warning),
          ),
        ],
        const SizedBox(height: Insets.x4),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: '收养它',
                icon: Icons.favorite_rounded,
                expand: true,
                onPressed: () => controller.adoptPreview(name: _name.text),
              ),
            ),
            const SizedBox(width: Insets.x2),
            PillButton(
              label: '重新生成',
              filled: false,
              onPressed: controller.generating
                  ? null
                  : () => controller.generate(style: _style, name: _name.text),
            ),
          ],
        ),
        const SizedBox(height: Insets.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              onPressed: controller.resetGeneration,
              child: const Text('换一张照片')),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 220, child: artwork),
                const SizedBox(height: Insets.x4),
                details,
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: artwork),
            const SizedBox(width: Insets.x5),
            Expanded(flex: 5, child: SingleChildScrollView(child: details)),
          ],
        );
      },
    );
  }
}

/// 照片选择区：悬停时虚线变 accent，给「这里可以点」的反馈。
class _HoverDropZone extends StatefulWidget {
  const _HoverDropZone({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverDropZone> createState() => _HoverDropZoneState();
}

class _HoverDropZoneState extends State<_HoverDropZone> {
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
          color: _hover ? accent : const Color(0xFFD9CFC1),
          background: _hover
              ? tintOf(accent, 0.05)
              : AppColors.surfaceAlt.withValues(alpha: 0.45),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 拍摄建议：照片生成的成败主要在照片本身，把三条硬要求直接写在表单里。
class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('正脸对镜头', '五官清楚，抠图锚点才准'),
      ('背景干净', '纯色墙面或桌面，边缘更好分离'),
      ('光线均匀', '避免大背光与强阴影'),
    ];
    return Container(
      padding:
          const EdgeInsets.fromLTRB(Insets.x3, Insets.x2, Insets.x3, Insets.x3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    size: 14, color: AppColors.inkSoft),
                const SizedBox(width: 6),
                Text('拍摄建议',
                    style: AppType.meta.copyWith(color: AppColors.inkSoft)),
              ],
            ),
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.check_rounded,
                        size: 12, color: AppColors.inkFaint),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${item.$1}  ',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink),
                          ),
                          TextSpan(
                            text: item.$2,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: AppColors.inkSoft),
                          ),
                        ],
                      ),
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
