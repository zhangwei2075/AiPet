import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/settings.dart';
import 'package:momopet/pet/motion.dart';
import 'package:momopet/state/controller_types.dart';

void main() {
  group('主动行为加权', () {
    test('无性格标签时四类都有机会，权重和为 5', () {
      final weights = proactiveWeights(const []);
      expect(weights.values.fold(0, (sum, w) => sum + w), 5);
      expect(proactiveKindAt(weights, 0), ProactiveKind.chat);
      expect(proactiveKindAt(weights, 1), ProactiveKind.chat);
      expect(proactiveKindAt(weights, 2), ProactiveKind.treat);
      expect(proactiveKindAt(weights, 3), ProactiveKind.cuddle);
      expect(proactiveKindAt(weights, 4), ProactiveKind.zoomies);
    });

    test('有财的性格（元气/黏人/贪吃）让三类专属行为都加权', () {
      final weights = proactiveWeights(const ['元气', '黏人', '贪吃']);
      expect(weights[ProactiveKind.chat], 2);
      expect(weights[ProactiveKind.treat], 6);
      expect(weights[ProactiveKind.cuddle], 5);
      expect(weights[ProactiveKind.zoomies], 5);
      expect(weights.values.fold(0, (sum, w) => sum + w), 18);

      // chat 0~1 / treat 2~7 / cuddle 8~12 / zoomies 13~17
      expect(proactiveKindAt(weights, 0), ProactiveKind.chat);
      expect(proactiveKindAt(weights, 2), ProactiveKind.treat);
      expect(proactiveKindAt(weights, 8), ProactiveKind.cuddle);
      expect(proactiveKindAt(weights, 13), ProactiveKind.zoomies);
    });

    test('单一性格只加权对应行为', () {
      final greedy = proactiveWeights(const ['吃货']);
      expect(greedy[ProactiveKind.treat], 6);
      expect(greedy[ProactiveKind.cuddle], 1);

      final lively = proactiveWeights(const ['好动']);
      expect(lively[ProactiveKind.zoomies], 5);
      expect(lively[ProactiveKind.treat], 1);
    });

    test('越界 ticket 安全回落到搭话', () {
      expect(proactiveKindAt(proactiveWeights(const []), 999), ProactiveKind.chat);
    });
  });

  group('主动行为开关', () {
    test('默认开启，且能 JSON 往返', () {
      const settings = AppSettings();
      expect(settings.proactive, isTrue);
      expect(AppSettings.fromJson(settings.toJson()).proactive, isTrue);

      final off = AppSettings.fromJson({...settings.toJson(), 'proactive': false});
      expect(off.proactive, isFalse);
      expect(off.copyWith(proactive: true).proactive, isTrue);
    });

    test('旧配置缺字段 / 字符串布尔都安全回落', () {
      expect(AppSettings.fromJson({}).proactive, isTrue);
      expect(AppSettings.fromJson({'proactive': 'false'}).proactive, isFalse);
      expect(AppSettings.fromJson({'proactive': 0}).proactive, isFalse);
    });
  });

  group('讨食姿态', () {
    test('eat 姿态数值有限且随时间变化', () {
      final a = MotionEngine.pose(PetMotion.eat, time: 0);
      final b = MotionEngine.pose(PetMotion.eat, time: 0.2);
      expect(a.offsetY.isFinite, isTrue);
      expect(a.scaleY.isFinite, isTrue);
      expect(a.rotation.isFinite, isTrue);
      expect(a.offsetY == b.offsetY && a.rotation == b.rotation, isFalse);
    });
  });
}
