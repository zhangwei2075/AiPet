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

  group('MotionEngine v2 交互动作', () {
    /// 所有姿态函数在完整时间/进度扫描内必须输出有限值，防止 NaN 污染渲染。
    void expectFinite(PetPose pose, String tag) {
      expect(pose.scaleX.isFinite, isTrue, reason: tag);
      expect(pose.scaleY.isFinite, isTrue, reason: tag);
      expect(pose.offsetX.isFinite, isTrue, reason: tag);
      expect(pose.offsetY.isFinite, isTrue, reason: tag);
      expect(pose.rotation.isFinite, isTrue, reason: tag);
    }

    test('stretch 是「下沉-保持-收回」的单峰包络', () {
      for (var i = 0; i <= 20; i++) {
        final pose = MotionEngine.stretch(i / 20);
        expectFinite(pose, 'stretch $i/20');
      }
      // 起手和收尾都回到静止
      expect(MotionEngine.stretch(0).offsetY, 0);
      expect(MotionEngine.stretch(1).offsetY, closeTo(0, 0.5));
      // 满弓时下沉、前倾、压扁
      final peak = MotionEngine.stretch(0.5);
      expect(peak.offsetY, greaterThan(4));
      expect(peak.rotation, greaterThan(0.05));
      expect(peak.scaleY, lessThan(1));
    });

    test('wag 有雀跃起伏和左右摆', () {
      var maxBounce = 0.0;
      for (var i = 0; i < 20; i++) {
        final pose = MotionEngine.wag(i * 0.1);
        expectFinite(pose, 'wag $i');
        maxBounce = math.max(maxBounce, pose.offsetY.abs());
      }
      expect(maxBounce, greaterThan(2));
    });

    test('shake 是高频甩动且幅度有界', () {
      var maxSway = 0.0;
      for (var i = 0; i < 40; i++) {
        final pose = MotionEngine.shake(i * 0.05);
        expectFinite(pose, 'shake $i');
        maxSway = math.max(maxSway, pose.offsetX.abs());
        expect(pose.rotation.abs(), lessThan(0.1));
      }
      expect(maxSway, greaterThan(3));
    });

    test('bark 两声脉冲，起止归零', () {
      expect(MotionEngine.bark(0).offsetY, 0);
      expect(MotionEngine.bark(1).offsetY, closeTo(0, 0.5));
      // 1/4 与 3/4 处是两次吠叫的峰
      expect(MotionEngine.bark(0.25).offsetY, lessThan(-2));
      expect(MotionEngine.bark(0.75).offsetY, lessThan(-2));
      // 峰间谷底回到放松
      expect(MotionEngine.bark(0.5).offsetY, closeTo(0, 0.5));
    });

    test('sniff 持续低头带颤动', () {
      final values = <double>[
        for (var i = 0; i < 10; i++) MotionEngine.sniff(i * 0.2).offsetY,
      ];
      expect(values.every((y) => y > 3), isTrue); // 全程低头
      expect(values.toSet().length, greaterThan(1)); // 有嗅闻颤动
    });

    test('celebrate 坐起后落回，起止归零', () {
      expect(MotionEngine.celebrate(0).offsetY, 0);
      expect(MotionEngine.celebrate(1).offsetY, closeTo(0, 0.5));
      final peak = MotionEngine.celebrate(0.5);
      expect(peak.offsetY, lessThan(-4)); // 升起
      expect(peak.rotation, lessThan(-0.1)); // 前身抬起
    });
  });
}
