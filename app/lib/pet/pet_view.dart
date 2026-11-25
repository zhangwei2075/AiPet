import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../ui/common.dart';
import '../ui/speech_bubble.dart';
import 'pet_stage.dart';

/// 悬浮在桌面上的宠物视图（窗口主体）。
class PetView extends StatefulWidget {
  const PetView({super.key, required this.controller});

  final AppController controller;

  @override
  State<PetView> createState() => _PetViewState();
}

class _PetViewState extends State<PetView> {
  final GlobalKey _bubbleKey = GlobalKey();
  final GlobalKey _toolsKey = GlobalKey();
  bool _hover = false;

  /// 把气泡和工具按钮的矩形合并上报给 WindowService，
  /// 否则在「穿透模式」下它们收不到点击（见 docs/platforms.md）。
  void _reportInteractiveAreas() {
    if (!widget.controller.isDesktop) return;
    Rect? union;
    for (final key in [_bubbleKey, _toolsKey]) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = Rect.fromLTWH(
        box.localToGlobal(Offset.zero).dx,
        box.localToGlobal(Offset.zero).dy,
        box.size.width,
        box.size.height,
      );
      union = union == null ? rect : union.expandToInclude(rect);
    }
    widget.controller.window.uiRect.value = union ?? Rect.zero;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pet = controller.active;
    final accent = pet?.accent ?? Theme.of(context).colorScheme.primary;
    final isDesktop = controller.isDesktop;

    if (pet == null) {
      return const Center(child: EmptyHint(text: '还没有宠物，去「生成」页领一只吧'));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportInteractiveAreas();
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final petSize = math.min(constraints.maxWidth - 18, 300 * controller.scale);
        final showTools = !isDesktop || _hover;
        // 气泡尾巴朝下，底部锚在宠物上沿再留一点缝：无论宠物缩放到多大，
        // 对话框都紧贴图片上方，不再被顶到窗口最上沿。
        const bubbleGap = 6.0;
        final bubbleSpace = constraints.maxHeight - petSize - bubbleGap - 4;
        final maxLines = bubbleSpace < 90 ? 2 : (bubbleSpace < 140 ? 3 : 5);
        return AnimatedBuilder(
          animation: controller.agentActivity,
          builder: (context, _) {
            final activity = controller.agentActivity;
            final status = activity.statusLine;
            return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Stack(
            children: [
              Positioned(
                bottom: petSize + bubbleGap,
                left: 8,
                right: 8,
                child: Center(
                  child: AnimatedSwitcher(
                    key: _bubbleKey,
                    duration: const Duration(milliseconds: 220),
                    child: controller.bubble != null
                        ? SpeechBubble(
                            key: ValueKey(controller.bubble),
                            text: controller.bubble!,
                            accent: accent,
                            maxWidth: math.min(constraints.maxWidth - 36, 320),
                            maxLines: maxLines,
                            status: status,
                            statusBusy: activity.busy,
                            statusOk: activity.lastOk,
                            onTap: controller.openChat,
                            onClose: controller.dismissBubble,
                          )
                        : BubbleHint(
                            key: const ValueKey('hint'),
                            text: controller.isSleeping ? '睡着啦…点一下叫醒' : '点我摸摸 · 拖动搬家 · 双击转圈',
                            accent: accent,
                            status: status,
                            statusBusy: activity.busy,
                            statusOk: activity.lastOk,
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Center(
                  child: RepaintBoundary(
                    child: PetStage(
                      controller: controller,
                      pet: pet,
                      size: petSize,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: showTools ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !showTools,
                    child: Column(
                      key: _toolsKey,
                      children: [
                        RoundIconButton(
                          icon: Icons.chat_bubble_rounded,
                          tooltip: '和它说说话',
                          onPressed: controller.openChat,
                        ),
                        const SizedBox(height: 6),
                        RoundIconButton(
                          icon: Icons.pets_rounded,
                          tooltip: '宠物与设置',
                          onPressed: () => controller.openPanel(PanelTab.gallery),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
            );
          },
        );
      },
    );
  }
}
