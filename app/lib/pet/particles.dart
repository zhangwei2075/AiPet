import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/pet.dart';
import '../state/app_controller.dart';
import '../ui/theme.dart';

class _Particle {
  _Particle({
    required this.kind,
    required this.position,
    required this.velocity,
    required this.size,
    required this.color,
    required this.life,
    required this.spin,
  });

  final PetBurst kind;
  Offset position;
  final Offset velocity;
  final double size;
  final Color color;
  final double life;
  final double spin;
  double age = 0;
  double rotation = 0;

  double get t => (age / life).clamp(0.0, 1.0);
  bool get dead => age >= life;
}

/// 爱心 / 星星 / 音符 / 怒气 / Zzz 粒子。
class PetParticles extends StatefulWidget {
  const PetParticles({
    super.key,
    required this.bursts,
    required this.size,
    required this.head,
    required this.accent,
  });

  final Stream<PetBurst> bursts;
  final double size;
  final Offset head;
  final Color accent;

  @override
  State<PetParticles> createState() => _PetParticlesState();
}

class _PetParticlesState extends State<PetParticles> with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final math.Random _random = math.Random();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  late Stream<PetBurst> _subscriptionSource;
  StreamSubscription<PetBurst>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _ticker = createTicker(_onTick)..start();
  }

  void _subscribe() {
    _subscriptionSource = widget.bursts;
    _subscription = widget.bursts.listen(_spawn);
  }

  @override
  void didUpdateWidget(covariant PetParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bursts != _subscriptionSource) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _spawn(PetBurst kind) {
    final count = switch (kind) {
      PetBurst.anger => 4,
      PetBurst.sleep => 3,
      _ => 6 + _random.nextInt(3),
    };
    final origin = Offset(widget.size * 0.5, widget.head.dy * widget.size);
    for (var i = 0; i < count; i++) {
      final spread = (i - (count - 1) / 2) / count;
      _particles.add(
        _Particle(
          kind: kind,
          position: origin + Offset(spread * widget.size * 0.42 + _random.nextDouble() * 10 - 5, _random.nextDouble() * 12),
          velocity: Offset(spread * 26 + _random.nextDouble() * 10 - 5, -36 - _random.nextDouble() * 26),
          size: (kind == PetBurst.anger ? 16.0 : 15.0) + _random.nextDouble() * 8,
          color: _colorFor(kind),
          life: 1.1 + _random.nextDouble() * 0.55,
          spin: (_random.nextDouble() - 0.5) * 2.2,
        ),
      );
    }
    if (_particles.length > 60) _particles.removeRange(0, _particles.length - 60);
    _frame.value++;
  }

  Color _colorFor(PetBurst kind) => switch (kind) {
        PetBurst.hearts => const Color(0xFFFF6F91),
        PetBurst.stars => const Color(0xFFFFC24B),
        PetBurst.anger => const Color(0xFFF2544B),
        PetBurst.sleep => const Color(0xFF8FB8E8),
        PetBurst.note => widget.accent,
      };

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.016 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_particles.isEmpty) return;
    for (final particle in _particles) {
      particle.age += dt;
      particle.rotation += particle.spin * dt;
      particle.position += Offset(
        particle.velocity.dx * dt + math.sin((particle.age + particle.spin) * 4) * 12 * dt,
        particle.velocity.dy * dt,
      );
    }
    _particles.removeWhere((particle) => particle.dead);
    _frame.value++;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _ParticlePainter(particles: _particles, repaint: _frame),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required Listenable repaint}) : super(repaint: repaint);

  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final opacity = particle.t < 0.75 ? 1.0 : (1 - (particle.t - 0.75) / 0.25).clamp(0.0, 1.0);
      final scale = particle.t < 0.2 ? particle.t / 0.2 : 1.0;
      canvas.save();
      canvas.translate(particle.position.dx, particle.position.dy);
      canvas.rotate(particle.rotation);
      canvas.scale(scale);
      _draw(canvas, particle, opacity);
      canvas.restore();
    }
  }

  void _draw(Canvas canvas, _Particle particle, double opacity) {
    final paint = Paint()..color = particle.color.withValues(alpha: opacity);
    final s = particle.size;
    switch (particle.kind) {
      case PetBurst.hearts:
        final path = Path()
          ..moveTo(0, s * 0.36)
          ..cubicTo(-s * 0.75, -s * 0.15, -s * 0.36, -s * 0.78, 0, -s * 0.28)
          ..cubicTo(s * 0.36, -s * 0.78, s * 0.75, -s * 0.15, 0, s * 0.36)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case PetBurst.stars:
        final path = Path()
          ..moveTo(0, -s * 0.58)
          ..quadraticBezierTo(s * 0.08, -s * 0.08, s * 0.58, 0)
          ..quadraticBezierTo(s * 0.08, s * 0.08, 0, s * 0.58)
          ..quadraticBezierTo(-s * 0.08, s * 0.08, -s * 0.58, 0)
          ..quadraticBezierTo(-s * 0.08, -s * 0.08, 0, -s * 0.58)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case PetBurst.anger:
        final stroke = Paint()
          ..color = particle.color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        for (final angle in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
          canvas.save();
          canvas.rotate(angle);
          canvas.drawLine(Offset(0, s * 0.2), Offset(0, s * 0.52), stroke);
          canvas.restore();
        }
        break;
      case PetBurst.note:
      case PetBurst.sleep:
        final painter = TextPainter(
          text: TextSpan(
            text: particle.kind == PetBurst.note ? '♪' : 'Z',
            style: TextStyle(
              color: particle.color.withValues(alpha: opacity),
              fontSize: s * 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

/// 照片宠物没有表情帧时，用绘制的方式补上腮红 / 闭眼 / 怒气。
class ExpressionOverlay extends StatelessWidget {
  const ExpressionOverlay({
    super.key,
    required this.mood,
    required this.size,
    required this.head,
    required this.headRadius,
    required this.blink,
  });

  final PetMood mood;
  final double size;
  final Offset head;
  final double headRadius;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size(size, size),
        painter: _ExpressionPainter(
          mood: mood,
          head: Offset(head.dx * size, head.dy * size),
          radius: headRadius * size,
          blink: blink,
        ),
      ),
    );
  }
}

class _ExpressionPainter extends CustomPainter {
  _ExpressionPainter({required this.mood, required this.head, required this.radius, required this.blink});

  final PetMood mood;
  final Offset head;
  final double radius;
  final bool blink;

  @override
  void paint(Canvas canvas, Size size) {
    final blush = Paint()..color = const Color(0xFFFF8FA3).withValues(alpha: 0.32);
    if (mood == PetMood.love || mood == PetMood.happy || blink) {
      for (final side in [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: head + Offset(side * radius * 0.62, radius * 0.22),
            width: radius * 0.5,
            height: radius * 0.24,
          ),
          blush,
        );
      }
    }

    final ink = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, radius * 0.035)
      ..strokeCap = StrokeCap.round;

    if (blink || mood == PetMood.sleepy) {
      for (final side in [-1.0, 1.0]) {
        final center = head + Offset(side * radius * 0.34, -radius * 0.02);
        final rect = Rect.fromCenter(center: center, width: radius * 0.42, height: radius * 0.2);
        canvas.drawArc(rect, 0.15, math.pi - 0.3, false, ink);
      }
    } else if (mood == PetMood.angry) {
      for (final side in [-1.0, 1.0]) {
        final start = head + Offset(side * radius * 0.12, -radius * 0.34);
        canvas.drawLine(start, start + Offset(side * radius * 0.4, radius * 0.1), ink);
      }
      final steam = Paint()
        ..color = const Color(0xFFF2544B).withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      final origin = head + Offset(radius * 1.15, -radius * 0.95);
      for (final angle in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
        canvas.save();
        canvas.translate(origin.dx, origin.dy);
        canvas.rotate(angle);
        canvas.drawLine(const Offset(0, 3), const Offset(0, 12), steam);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExpressionPainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.blink != blink || oldDelegate.radius != radius;
}
