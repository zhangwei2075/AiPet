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
    _action.duration = _actionDuration(action);
    _action.forward(from: 0);
  }

  /// 一次性动作时长：petpack 有对应序列时按「帧数 / fps」精确对齐，
  /// 播完正好走完一遍帧；没有序列时用程序化姿态的兜底时长。
  Duration _actionDuration(PetAction action) {
    final motion = switch (action) {
      PetAction.hop => PetMotion.hop,
      PetAction.spin => PetMotion.spin,
      PetAction.drop => PetMotion.drop,
      PetAction.shake => PetMotion.shake,
      PetAction.celebrate => PetMotion.celebrate,
      PetAction.stretch => PetMotion.stretch,
      PetAction.bark => PetMotion.bark,
      PetAction.none => PetMotion.idle,
    };
    final seq = widget.pet.animations[motion.name];
    if (seq != null && seq.frames.isNotEmpty && seq.fps > 0) {
      return Duration(milliseconds: (seq.frames.length / seq.fps * 1000).round());
    }
    return switch (action) {
      PetAction.hop => const Duration(milliseconds: 560),
      PetAction.spin => const Duration(milliseconds: 780),
      PetAction.drop => const Duration(milliseconds: 420),
      PetAction.shake => const Duration(milliseconds: 660),
      PetAction.celebrate => const Duration(milliseconds: 1000),
      PetAction.stretch => const Duration(milliseconds: 1600),
      PetAction.bark => const Duration(milliseconds: 860),
      PetAction.none => const Duration(milliseconds: 320),
    };
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
        PetAction.shake => PetMotion.shake,
        PetAction.celebrate => PetMotion.celebrate,
        PetAction.stretch => PetMotion.stretch,
        PetAction.bark => PetMotion.bark,
        PetAction.none => PetMotion.idle,
      };
    }
    if (controller.eating) return PetMotion.eat;
    if (controller.begging) return PetMotion.lie;
    if (controller.running) return PetMotion.run;
    if (controller.walking) return PetMotion.walk;
    if (controller.wagging) return PetMotion.wag;
    if (controller.sniffing) return PetMotion.sniff;
    return switch (controller.mood) {
      PetMood.angry => PetMotion.angry,
      PetMood.sleepy => PetMotion.sleepy,
      PetMood.talk => PetMotion.talk,
      PetMood.happy || PetMood.love => PetMotion.talk,
      _ => PetMotion.idle,
    };
  }

  /// Petdex 风格：左右朝向是**独立的状态行**（run-right / run-left），
  /// 而不是运行时把整张图镜像、更不是绕图像中心旋转。
  PetAnimSequence? _animationFor(PetMotion motion, AppController controller) {
    final name = motion.name;
    if (controller.facing < 0 &&
        (motion == PetMotion.walk || motion == PetMotion.run)) {
      final left = widget.pet.animations['${name}_left'];
      if (left != null) return left;
    }
    return widget.pet.animations[name];
  }

  /// 这些一次性动作的帧号代表动作进度（播一遍），不按 fps 循环。
  bool _isOneShotIndexed(PetMotion motion) =>
      motion == PetMotion.spin ||
      motion == PetMotion.shake ||
      motion == PetMotion.celebrate ||
      motion == PetMotion.stretch ||
      motion == PetMotion.bark;

  PetMood _frameMood(AppController controller) {
    if (controller.dragging) return PetMood.happy;
    if (controller.petting || controller.begging) return PetMood.love;
    if (controller.running) return PetMood.happy;
    if (controller.eating) return PetMood.love;
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
              final mood = _frameMood(controller);
              final hasFrame = pet.frames.containsKey(mood);
              final frameMood = hasFrame ? mood : PetMood.idle;

              final anim = _animationFor(motion, controller);
              String? animFile;
              // 照片宠物通常只有 idle 一帧，其余表情靠 ExpressionOverlay 叠加。
              // 有 idle 呼吸动画时，非 idle 表情要让位给 overlay，否则表情会被呼吸帧盖住。
              final expressionFallback =
                  motion == PetMotion.idle && mood != PetMood.idle && !hasFrame;
              if (anim != null && anim.frames.isNotEmpty && !expressionFallback) {
                if (_isOneShotIndexed(motion) && _action.isAnimating) {
                  // 一次性帧动作：帧号跟动作进度走，播一遍正好走完序列；
                  // spin 的帧内已含柱面透视，这里不再叠任何 2D 旋转或倾斜。
                  final index = (_action.value * anim.frames.length)
                      .floor()
                      .clamp(0, anim.frames.length - 1);
                  animFile = anim.frameAtIndex(index);
                } else {
                  // 用单调时钟取帧：_clock 每 20 秒回绕一次，直接拿它算帧号会在回绕时跳帧。
                  final time = _animClock.elapsedMilliseconds / 1000.0;
                  animFile = anim.frameAt(time);
                }
                pose = const PetPose().lerp(pose, 0.25);
              }

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
