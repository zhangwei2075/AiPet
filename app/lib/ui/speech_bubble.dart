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
  });

  final String text;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final double maxWidth;

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
              padding: const EdgeInsets.fromLTRB(16, 11, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6B4E3C).withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink),
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
                          child: Icon(Icons.close_rounded, size: 14, color: AppColors.inkSoft),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          CustomPaint(
            size: const Size(18, 9),
            painter: _TailPainter(color: Colors.white.withValues(alpha: 0.97), border: accent.withValues(alpha: 0.35)),
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
  bool shouldRepaint(covariant _TailPainter oldDelegate) => oldDelegate.color != color;
}

/// 宠物没有气泡时，露出一句轻提示。
class BubbleHint extends StatelessWidget {
  const BubbleHint({super.key, required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.9,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 12, color: accent),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
          ],
        ),
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

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

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
