import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/models/pet.dart';
import 'package:momopet/pet/motion.dart';

void main() {
  group('绕垂直轴转身（Petdex 范式）', () {
    test('spin 姿态不含 2D 旋转、不抬脚、不倾斜', () {
      for (var i = 0; i <= 20; i++) {
        final pose = MotionEngine.spin(i / 20);
        // rotation 是绕图像中心的 2D 旋转，转身绝不能用它。
        expect(pose.rotation, 0, reason: 'progress=$i/20 出现了平面旋转');
        expect(pose.offsetY, 0, reason: '脚底必须贴地');
        expect(pose.scaleY, 1);
      }
    });

    test('spin 只在水平面内左右微动', () {
      final values = <double>[
        for (var i = 0; i <= 10; i++) MotionEngine.spin(i / 10).offsetX,
      ];
      expect(values.any((v) => v != 0), isTrue);
      expect(values.every((v) => v.abs() <= 3.0001), isTrue);
    });

    test('方向帧按序号循环，空序列安全返回空串', () {
      const seq = PetAnimSequence(fps: 12, frames: ['a', 'b', 'c']);
      expect(seq.frameAtIndex(0), 'a');
      expect(seq.frameAtIndex(1), 'b');
      expect(seq.frameAtIndex(3), 'a');
      expect(seq.frameAtIndex(7), 'b');
      expect(const PetAnimSequence(fps: 8, frames: []).frameAtIndex(5), '');
    });
  });

  group('其它动作仍按时间取帧', () {
    test('frameAt 用单调秒数，不依赖 20 秒回绕', () {
      const seq = PetAnimSequence(fps: 8, frames: ['a', 'b', 'c', 'd']);
      expect(seq.frameAt(0), 'a');
      expect(seq.frameAt(0.25), 'c');
      expect(seq.frameAt(20.125), 'b');
    });
  });
}
