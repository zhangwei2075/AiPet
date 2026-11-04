import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// 一块显示器的工作区（逻辑像素，已扣除任务栏）。
@immutable
class DisplayArea {
  const DisplayArea({required this.id, required this.bounds});

  factory DisplayArea.fromDisplay(Display display) {
    final origin = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return DisplayArea(id: display.id, bounds: origin & size);
  }

  final String id;
  final Rect bounds;

  @override
  String toString() => 'DisplayArea($id, $bounds)';
}

/// 选窗口所在的显示器：优先取与窗口重叠面积最大的，完全在屏幕外时取中心最近的。
DisplayArea? displayForRect(Rect window, Iterable<DisplayArea> displays) {
  DisplayArea? best;
  var bestOverlap = 0.0;
  for (final display in displays) {
    final overlap = _intersectionArea(window, display.bounds);
    if (overlap > bestOverlap) {
      best = display;
      bestOverlap = overlap;
    }
  }
  if (best != null) return best;

  final center = window.center;
  var bestDistance = double.infinity;
  for (final display in displays) {
    final distance = (display.bounds.center - center).distanceSquared;
    if (distance < bestDistance) {
      best = display;
      bestDistance = distance;
    }
  }
  return best;
}

/// 把窗口左上角夹到显示器工作区内；窗口比显示器大时保留左上角。
Offset clampToArea(Offset position, Size windowSize, Rect area) {
  final maxX = math.max(area.left, area.right - windowSize.width);
  final maxY = math.max(area.top, area.bottom - windowSize.height);
  return Offset(
    position.dx.clamp(area.left, maxX),
    position.dy.clamp(area.top, maxY),
  );
}

/// 横向走 [dx] 后夹回同一块显示器。y 不动，避免宠物上下漂移。
Offset clampGlideTarget({
  required Offset start,
  required double dx,
  required Size windowSize,
  required Rect area,
}) {
  final target = clampToArea(Offset(start.dx + dx, start.dy), windowSize, area);
  return Offset(target.dx, start.dy);
}

double _intersectionArea(Rect a, Rect b) {
  final left = math.max(a.left, b.left);
  final top = math.max(a.top, b.top);
  final right = math.min(a.right, b.right);
  final bottom = math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) return 0;
  return (right - left) * (bottom - top);
}
