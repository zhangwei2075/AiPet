import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class SpeechBubble extends StatelessWidget {
  const SpeechBubble({
    super.key,
    required this.text,
    required this.accent,
    this.onTap,
    this.onClose,
    this.maxWidth = 320,
    this.maxLines = 5,
    this.status,
    this.statusBusy = false,
    this.statusOk = true,
  });

  final String text;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final double maxWidth;
  final int maxLines;

  /// 当前正在执行的任务状态（由 AgentActivity 提供），null 时不占版面。
  final String? status;
  final bool statusBusy;
  final bool statusOk;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Transform.scale(scale: 0.94 + 0.06 * value, child: child),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: AppColors.line),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B2A1C).withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          text,
                          maxLines: maxLines,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, height: 1.5, color: AppColors.ink),
                        ),
                      ),
                      if (onClose != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InkWell(
                            onTap: onClose,
                            borderRadius: BorderRadius.circular(20),
                            child: const Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: AppColors.inkSoft),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (status != null) ...[
                    const SizedBox(height: 7),
                    TaskStatusChip(
                      status: status!,
                      accent: accent,
                      busy: statusBusy,
                      ok: statusOk,
                    ),
                  ],
                ],
              ),
            ),
          ),
          CustomPaint(
            size: const Size(18, 9),
            painter:
                _TailPainter(color: AppColors.surface, border: AppColors.line),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter({required this.color, required this.border});

  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.5, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(covariant _TailPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 宠物没有气泡时，露出一句轻提示；有任务在跑时同时挂一条状态。
class BubbleHint extends StatelessWidget {
  const BubbleHint({
    super.key,
    required this.text,
    required this.accent,
    this.status,
    this.statusBusy = false,
    this.statusOk = true,
  });

  final String text;
  final Color accent;
  final String? status;
  final bool statusBusy;
  final bool statusOk;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.9,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(
              status == null ? Radii.pill : Radii.control),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 12, color: accent),
                const SizedBox(width: 6),
                Text(text,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: 6),
              TaskStatusChip(
                status: status!,
                accent: accent,
                busy: statusBusy,
                ok: statusOk,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一行任务状态：气泡内与聊天窗口共用，避免两处各画一套。
class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({
    super.key,
    required this.status,
    required this.accent,
    this.busy = false,
    this.ok = true,
    this.maxWidth = 280,
  });

  final String status;
  final Color accent;
  final bool busy;
  final bool ok;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final color =
        busy ? AppColors.warning : (ok ? AppColors.success : AppColors.danger);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          else
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 11, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, height: 1.35, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color});

  final Color color;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value * 3 - index).clamp(0.0, 1.0);
            final lift = math.sin(phase * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.6),
              child: Transform.translate(
                offset: Offset(0, -3 * lift),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.45 + 0.5 * lift),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
