import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:momopet/services/display_bounds.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() {
  const primary = DisplayArea(id: 'primary', bounds: Rect.fromLTWH(0, 0, 1920, 1040));
  const right = DisplayArea(id: 'right', bounds: Rect.fromLTWH(1920, 0, 1920, 1040));
  const left = DisplayArea(id: 'left', bounds: Rect.fromLTWH(-1920, 0, 1920, 1040));
  const above = DisplayArea(id: 'above', bounds: Rect.fromLTWH(0, -1080, 1920, 1080));

  test('工作区取 visiblePosition + visibleSize，自动扣除任务栏', () {
    const display = Display(
      id: 'x',
      size: Size(1920, 1080),
      visiblePosition: Offset(0, 0),
      visibleSize: Size(1920, 1040),
    );

    expect(
      DisplayArea.fromDisplay(display).bounds,
      const Rect.fromLTWH(0, 0, 1920, 1040),
    );
  });

  test('没有 visiblePosition / visibleSize 时退回 size 和 (0,0)', () {
    const display = Display(id: 'fallback', size: Size(1280, 720));
    expect(
      DisplayArea.fromDisplay(display).bounds,
      const Rect.fromLTWH(0, 0, 1280, 720),
    );
  });

  test('窗口跨两块屏时选重叠面积更大的那块', () {
    // 左屏 40px，右屏 180px
    const window = Rect.fromLTWH(1880, 100, 220, 280);
    expect(displayForRect(window, [primary, right])?.id, 'right');
  });

  test('支持负坐标的左侧副屏', () {
    expect(
      displayForRect(const Rect.fromLTWH(-500, 100, 220, 280), [primary, left])?.id,
      'left',
    );
    expect(
      displayForRect(const Rect.fromLTWH(100, 100, 220, 280), [primary, left])?.id,
      'primary',
    );
  });

  test('支持上方副屏', () {
    expect(
      displayForRect(const Rect.fromLTWH(100, -500, 220, 280), [primary, above])?.id,
      'above',
    );
  });

  test('窗口完全在屏幕外时退回最近的显示器', () {
    expect(
      displayForRect(const Rect.fromLTWH(-3000, -3000, 220, 280), [primary, right])?.id,
      'primary',
    );
    expect(
      displayForRect(const Rect.fromLTWH(5000, 100, 220, 280), [primary, right])?.id,
      'right',
    );
  });

  test('边界夹取使用副屏的 left/right，而不是主屏的 0', () {
    const size = Size(220, 280);
    expect(clampToArea(const Offset(3800, 100), size, right.bounds), const Offset(3620, 100));
    expect(clampToArea(const Offset(1000, 100), size, right.bounds), const Offset(1920, 100));
    expect(clampToArea(const Offset(2000, -50), size, right.bounds), const Offset(2000, 0));
  });

  test('窗口比显示器还大时保留左上角', () {
    expect(
      clampToArea(const Offset(100, 100), const Size(3000, 2000), primary.bounds),
      const Offset(0, 0),
    );
  });

  test('走动目标夹回当前显示器，y 保持不变', () {
    const size = Size(220, 280);
    expect(
      clampGlideTarget(
        start: const Offset(3500, 200),
        dx: 500,
        windowSize: size,
        area: right.bounds,
      ),
      const Offset(3620, 200),
    );
    expect(
      clampGlideTarget(
        start: const Offset(2000, 200),
        dx: -500,
        windowSize: size,
        area: right.bounds,
      ),
      const Offset(1920, 200),
    );
  });
}
