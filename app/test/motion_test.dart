import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/pet/motion.dart';

void main() {
  group('PetPose', () {
    test('merge combines transforms additively', () {
      final merged = const PetPose(
        scaleX: 1.1,
        scaleY: 0.9,
        offsetX: 4,
        offsetY: -6,
        rotation: 0.2,
      ).merge(const PetPose(
        scaleX: 1.05,
        scaleY: 1.02,
        offsetX: 2,
        offsetY: 3,
        rotation: -0.1,
      ));
      expect(merged.scaleX, closeTo(1.155, 0.0001));
      expect(merged.scaleY, closeTo(0.918, 0.0001));
      expect(merged.offsetX, closeTo(6, 0.0001));
      expect(merged.offsetY, closeTo(-3, 0.0001));
      expect(merged.rotation, closeTo(0.1, 0.0001));
    });

    test('lerp interpolates every component', () {
      final mid = const PetPose(scaleX: 1.0, offsetX: 0, rotation: 0)
          .lerp(const PetPose(scaleX: 1.2, offsetX: 10, rotation: 0.4), 0.5);
      expect(mid.scaleX, closeTo(1.1, 0.0001));
      expect(mid.offsetX, closeTo(5, 0.0001));
      expect(mid.rotation, closeTo(0.2, 0.0001));
    });
  });

  group('MotionEngine.run', () {
    test('leans forward and bounces harder than walk', () {
      double maxAbsRunY = 0;
      double maxAbsWalkY = 0;
      for (var i = 0; i < 40; i++) {
        final t = i * 0.05;
        final run = MotionEngine.run(t);
        final walk = MotionEngine.walk(t);
        expect(run.rotation, lessThan(0)); // 前倾
        expect(run.scaleX, inInclusiveRange(0.9, 1.2));
        expect(run.scaleY, inInclusiveRange(0.9, 1.1));
        expect(run.offsetY, inInclusiveRange(-14, 2));
        maxAbsRunY = math.max(maxAbsRunY, run.offsetY.abs());
        maxAbsWalkY = math.max(maxAbsWalkY, walk.offsetY.abs());
      }
      expect(maxAbsRunY, greaterThanOrEqualTo(maxAbsWalkY));
      expect(maxAbsRunY, greaterThan(5)); // 明显腾空感
    });
  });

  group('MotionEngine.lie', () {
    test('squashes, tilts, sinks and breathes on a 3.2s cycle', () {
      double minY = double.infinity;
      double maxY = double.negativeInfinity;
      for (var i = 0; i < 64; i++) {
        final t = i * 0.125;
        final pose = MotionEngine.lie(t, 0.7);
        expect(pose.scaleY, lessThan(0.85)); // 压扁
        expect(pose.scaleX, greaterThan(1.0)); // 摊宽
        expect(pose.rotation, inInclusiveRange(0.4, 0.8)); // 侧躺倾角
        expect(pose.offsetY, greaterThan(15)); // 下沉贴近地面
        minY = math.min(minY, pose.scaleY);
        maxY = math.max(maxY, pose.scaleY);
      }
      // 呼吸周期 3.2s：scaleY 在 0.76±0.02 之间波动
      expect(maxY - minY, inInclusiveRange(0.005, 0.06));
    });
  });

  group('MotionEngine basics', () {
    test('idle is subtle', () {
      for (var i = 0; i < 20; i++) {
        final pose = MotionEngine.idle(i * 0.3, 1.2);
        expect(pose.offsetY.abs(), lessThan(6));
        expect(pose.rotation.abs(), lessThan(0.12));
      }
    });

    test('walk stays subtle', () {
      for (var i = 0; i < 20; i++) {
        final pose = MotionEngine.walk(i * 0.25);
        expect(pose.offsetY.abs(), lessThan(6));
        expect(pose.rotation.abs(), lessThan(0.1));
      }
    });
  });
}
