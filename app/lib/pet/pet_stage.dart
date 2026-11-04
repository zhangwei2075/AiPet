import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../state/app_controller.dart';
import 'motion.dart';
import 'particles.dart';

/// 宠物本体：帧动画 + 程序化动作 + 触摸手势 + 粒子。
class PetStage extends StatefulWidget {
  const PetStage({
    super.key,
    required this.controller,
    required this.pet,
    required this.size,
  });

  final AppController controller;
  final Pet pet;
  final double size;

  @override
  State<PetStage> createState() => _PetStageState();
}

class _PetStageState extends State<PetStage> with TickerProviderStateMixin {
  late final AnimationController _clock;
  late final AnimationController _action;
  late final Listenable _ticker;
  final math.Random _random = math.Random();
  final Stopwatch _animClock = Stopwatch()..start();
  Timer? _blinkTimer;
  bool _blink = false;
  bool _blinking = false;
  int _lastSeed = 0;
  PetAction _currentAction = PetAction.none;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
    _action = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    // 帧动画和程序化姿态都靠这两个 controller 驱动；必须有人监听才会逐帧重建。
    _ticker = Listenable.merge([_clock, _action]);
    _action.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _currentAction = PetAction.none;
        widget.controller.completeAction();
      }
    });
    _lastSeed = widget.controller.actionSeed;
    _scheduleBlink();
  }

  @override
  void didUpdateWidget(covariant PetStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.actionSeed != _lastSeed) {
      _lastSeed = widget.controller.actionSeed;
      _playAction(widget.controller.action);
    }
    if (oldWidget.pet.id != widget.pet.id) {
      _currentAction = PetAction.none;
    }
    if (oldWidget.pet.id != widget.pet.id || oldWidget.pet.animations != widget.pet.animations) {
      _precacheAnimationFrames();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAnimationFrames();
  }

  /// 预解码所有动作帧：首次走动 / 跑步时不再等磁盘解码，避免第一圈卡顿。
  void _precacheAnimationFrames() {
    final pet = widget.pet;
    if (pet.animations.isEmpty) return;
    final files = <String>{
      for (final sequence in pet.animations.values) ...sequence.frames,
    };
    for (final file in files) {
      precacheImage(pet.imageForFile(file), context, onError: (_, __) {});
    }
  }

  void _playAction(PetAction action) {
    if (action == PetAction.none) return;
    _currentAction = action;
    _action.duration = switch (action) {
      PetAction.hop => const Duration(milliseconds: 560),
      PetAction.spin => const Duration(milliseconds: 780),
      PetAction.drop => const Duration(milliseconds: 420),
      PetAction.none => const Duration(milliseconds: 320),
    };
    _action.forward(from: 0);
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2400 + _random.nextInt(3600)), () async {
      if (!mounted) return;
      final controller = widget.controller;
      if (!controller.isSleeping && !controller.dragging && !_blinking) {
        _blinking = true;
        setState(() => _blink = true);
        await Future<void>.delayed(const Duration(milliseconds: 115));
        if (!mounted) return;
        setState(() => _blink = false);
        _blinking = false;
      }
      _scheduleBlink();
    });
  }

  bool _isHead(Offset local) {
    final anchors = widget.pet.anchors;
    final nx = local.dx / widget.size;
    final ny = local.dy / widget.size;
    final rx = anchors.headRadius * 1.15;
    final dx = (nx - anchors.head.dx) / rx;
    final dy = (ny - anchors.head.dy) / rx;
    return dx * dx + dy * dy <= 1;
  }

  void _reportHitArea() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero);
    widget.controller.window.hitRect.value =
        Rect.fromLTWH(offset.dx, offset.dy, box.size.width, box.size.height);
  }

  PetMotion _resolveMotion(AppController controller) {
    if (controller.dragging) {
      // 拖动时直接复用走路动画；方向由 facing 控制，停住也继续迈步。
      if (widget.pet.animations.containsKey('walk')) return PetMotion.walk;
      return PetMotion.drag;
    }
    if (controller.petting) return PetMotion.pat;
    if (_action.isAnimating) {
      return switch (_currentAction) {
        PetAction.hop => PetMotion.hop,
        PetAction.spin => PetMotion.spin,
        PetAction.drop => PetMotion.drop,
        PetAction.none => PetMotion.idle,
      };
    }
    if (controller.begging) return PetMotion.lie;
    if (controller.running) return PetMotion.run;
    if (controller.walking) return PetMotion.walk;
    return switch (controller.mood) {
      PetMood.angry => PetMotion.angry,
      PetMood.sleepy => PetMotion.sleepy,
      PetMood.talk => PetMotion.talk,
      PetMood.happy || PetMood.love => PetMotion.talk,
      _ => PetMotion.idle,
    };
  }

  PetMood _frameMood(AppController controller) {
    if (controller.dragging) return PetMood.happy;
    if (controller.petting || controller.begging) return PetMood.love;
    if (controller.running) return PetMood.happy;
    if (_currentAction == PetAction.hop && _action.isAnimating) return PetMood.happy;
    if (_blink) return PetMood.blink;
    return controller.mood;
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _clock.dispose();
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pet = widget.pet;
    final size = widget.size;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportHitArea();
    });

    return MouseRegion(
      cursor: controller.dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          controller.tapPet(head: _isHead(details.localPosition));
        },
        onPanStart: (_) => controller.beginWindowDrag(),
        onLongPressStart: (_) => controller.startPetting(),
        onLongPressEnd: (_) => controller.stopPetting(),
        onLongPressCancel: controller.stopPetting,
        child: SizedBox(
          width: size,
          height: size,
          child: AnimatedBuilder(
            animation: _ticker,
            builder: (context, _) {
              final motion = _resolveMotion(controller);
              var pose = MotionEngine.pose(
                motion,
                time: _clock.value * 20,
                progress: _action.value,
                phase: (pet.id.hashCode % 100) / 30,
              );
              // 逐帧动画（flipbook）：petpack 带 walk/run/lie 动画序列时按 fps 循环播放真实帧，
              // 程序化姿态衰减到 25% 仅叠加微动，避免与帧内已绘姿态（如躺倒倾斜）叠加；
              // 无动画序列的动作（拖拽 / 点击 / 睡觉等）仍走纯程序化姿态。
              final anim = pet.animations[motion.name];
              String? animFile;
              if (anim != null && anim.frames.isNotEmpty) {
                // 用单调时钟取帧：_clock 每 20 秒回绕一次，直接拿它算帧号会在回绕时跳帧。
                final time = _animClock.elapsedMilliseconds / 1000.0;
                animFile = anim.frameAt(time);
                pose = const PetPose().lerp(pose, 0.25);
              }

              final mood = _frameMood(controller);
              final hasFrame = pet.frames.containsKey(mood);
              final frameMood = hasFrame ? mood : PetMood.idle;

              final petImage = Stack(
                alignment: Alignment.center,
                children: [
                  Image(
                    image: animFile != null ? pet.imageForFile(animFile) : pet.imageFor(frameMood),
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                  if (!hasFrame && animFile == null)
                    ExpressionOverlay(
                      mood: controller.mood,
                      blink: _blink,
                      size: size,
                      head: pet.anchors.head,
                      headRadius: pet.anchors.headRadius,
                    ),
                ],
              );

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    bottom: size * 0.015,
                    child: Container(
                      width: size * 0.56,
                      height: size * 0.12,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: RadialGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.20),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Transform.translate(
                      offset: Offset(pose.offsetX, pose.offsetY),
                      child: Transform.rotate(
                        angle: pose.rotation,
                        child: Transform.scale(
                          // 帧原画朝左；向右移动时水平镜像（向左跑 / 向右跑）
                          scaleX: pose.scaleX * (controller.facing > 0 ? -1.0 : 1.0),
                          scaleY: pose.scaleY,
                          alignment: Alignment.bottomCenter,
                          child: petImage,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: PetParticles(
                      bursts: controller.bursts,
                      size: size,
                      head: pet.anchors.head,
                      accent: pet.accent,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
