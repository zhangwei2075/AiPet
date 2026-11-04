import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 一次姿态变换：缩放 / 位移 / 旋转。
@immutable
class PetPose {
  const PetPose({
    this.scaleX = 1,
    this.scaleY = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.rotation = 0,
  });

  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;
  final double rotation;

  static const rest = PetPose();

  PetPose merge(PetPose other) => PetPose(
        scaleX: scaleX * other.scaleX,
        scaleY: scaleY * other.scaleY,
        offsetX: offsetX + other.offsetX,
        offsetY: offsetY + other.offsetY,
        rotation: rotation + other.rotation,
      );

  PetPose lerp(PetPose other, double t) => PetPose(
        scaleX: scaleX + (other.scaleX - scaleX) * t,
        scaleY: scaleY + (other.scaleY - scaleY) * t,
        offsetX: offsetX + (other.offsetX - offsetX) * t,
        offsetY: offsetY + (other.offsetY - offsetY) * t,
        rotation: rotation + (other.rotation - rotation) * t,
      );
}

enum PetMotion { idle, hop, drag, drop, angry, sleepy, talk, pat, spin, walk, run, lie }

/// 纯函数动画引擎：不依赖 Flutter 渲染，方便单元测试。
class MotionEngine {
  const MotionEngine._();

  /// [time] 秒；[progress] 0~1 的一次性动作进度；[phase] 用于让每只宠物略有差异。
  static PetPose pose(
    PetMotion motion, {
    required double time,
    double progress = 0,
    double phase = 0,
  }) {
    switch (motion) {
      case PetMotion.idle:
        return idle(time, phase);
      case PetMotion.hop:
        return hop(progress);
      case PetMotion.drag:
        return drag(time);
      case PetMotion.drop:
        return drop(progress);
      case PetMotion.angry:
        return angry(time, progress);
      case PetMotion.sleepy:
        return sleepy(time, phase);
      case PetMotion.talk:
        return talk(time);
      case PetMotion.pat:
        return pat(time);
      case PetMotion.spin:
        return spin(progress);
      case PetMotion.walk:
        return walk(time);
      case PetMotion.run:
        return run(time);
      case PetMotion.lie:
        return lie(time, phase);
    }
  }

  static PetPose idle(double time, double phase) {
    final breath = math.sin(2 * math.pi * time / 2.6 + phase);
    return PetPose(
      scaleX: 1 - 0.014 * breath,
      scaleY: 1 + 0.026 * breath,
      offsetY: -1.6 * (0.5 + 0.5 * breath),
      rotation: 0.012 * math.sin(2 * math.pi * time / 5.4 + phase),
    );
  }

  static PetPose hop(double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (p < 0.16) {
      final k = p / 0.16;
      return PetPose(scaleX: 1 + 0.10 * k, scaleY: 1 - 0.10 * k);
    }
    final u = (p - 0.16) / 0.84;
    final arc = math.sin(math.pi * u);
    return PetPose(
      offsetY: -74 * arc,
      scaleX: 1 - 0.035 * arc,
      scaleY: 1 + 0.05 * arc,
      rotation: -0.04 * math.sin(math.pi * u * 2),
    );
  }

  static PetPose drag(double time) => PetPose(
        scaleX: 0.965,
        scaleY: 1.045,
        offsetY: -3,
        rotation: 0.09 * math.sin(time * 4.2),
      );

  static PetPose drop(double progress) {
    final p = progress.clamp(0.0, 1.0);
    final settle = math.sin(p * math.pi * 3) * (1 - p);
    return PetPose(
      scaleX: 1 + 0.07 * settle,
      scaleY: 1 - 0.07 * settle,
      offsetY: 4 * settle,
    );
  }

  static PetPose angry(double time, double progress) {
    final decay = 1 - progress.clamp(0.0, 1.0) * 0.6;
    return PetPose(
      scaleX: 1.035,
      scaleY: 0.975,
      offsetX: 5.5 * math.sin(time * 34) * decay,
      rotation: 0.012 * math.sin(time * 30),
    );
  }

  static PetPose sleepy(double time, double phase) {
    final breath = math.sin(2 * math.pi * time / 4.6 + phase);
    return PetPose(
      scaleY: 1 + 0.035 * breath,
      scaleX: 1 - 0.012 * breath,
      offsetY: 2,
      rotation: 0.02 * math.sin(time * 0.6),
    );
  }

  static PetPose talk(double time) => PetPose(
        offsetY: -2.2 * math.sin(time * 7.5).abs(),
        scaleY: 1 + 0.012 * math.sin(time * 15),
        rotation: 0.01 * math.sin(time * 3),
      );

  static PetPose pat(double time) => PetPose(
        scaleY: 0.945 + 0.012 * math.sin(time * 22),
        scaleX: 1.045,
        offsetY: 3,
        rotation: 0.02 * math.sin(time * 9),
      );

  static PetPose spin(double progress) {
    final p = progress.clamp(0.0, 1.0);
    return PetPose(
      rotation: 2 * math.pi * p,
      offsetY: -14 * math.sin(math.pi * p),
      scaleX: 1 - 0.05 * math.sin(math.pi * p),
      scaleY: 1 - 0.05 * math.sin(math.pi * p),
    );
  }

  /// 慢走：小幅度上下颠 + 左右晃。
  static PetPose walk(double time) => PetPose(
        offsetY: -5 * math.sin(time * 9).abs(),
        rotation: 0.045 * math.sin(time * 9),
        scaleY: 1 + 0.018 * math.sin(time * 18),
        scaleX: 1 - 0.012 * math.sin(time * 18),
      );

  /// 小跑：步频更高、颠得更狠、整体前倾拉伸，看起来有冲劲。
  static PetPose run(double time) {
    final stride = math.sin(time * 13);
    return PetPose(
      offsetY: -11 * stride.abs(),
      rotation: -0.10 + 0.045 * stride,
      offsetX: 3.5 * stride,
      scaleX: 1 + 0.05 * stride.abs(),
      scaleY: 1 - 0.035 * stride.abs(),
    );
  }

  /// 躺倒求抚摸：压扁 + 下沉 + 轻微侧躺，配合呼吸微微起伏，偶尔晃两下撒娇。
  static PetPose lie(double time, double phase) {
    final breath = math.sin(2 * math.pi * time / 3.2 + phase);
    final wiggle = math.sin(time * 2.1 + phase * 2) * math.max(0, math.sin(time * 0.45));
    return PetPose(
      rotation: 0.52 + 0.035 * breath + 0.05 * wiggle,
      scaleX: 1.12 - 0.012 * breath,
      scaleY: 0.76 + 0.02 * breath,
      offsetY: 26 - 2 * breath,
    );
  }
}
