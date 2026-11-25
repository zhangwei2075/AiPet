import 'package:flutter/material.dart';

import 'theme.dart';

/// 功能开关说明的统一出口：说明文字只放在 Tooltip 里，鼠标悬停（触屏长按）才出现。
///
/// 这样开关卡片保持紧凑，又能在用户真正犹豫某个开关时给到完整解释。
/// 用法：把整行开关包进 [FeatureHelp]，标题用 [helpTitle] 显示一个 ⓘ 标记。
class FeatureHelp extends StatelessWidget {
  const FeatureHelp({
    super.key,
    required this.label,
    required this.description,
    required this.child,
  });

  final String label;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: TextSpan(
        style: const TextStyle(fontSize: 12, height: 1.55, color: Colors.white),
        children: [
          TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '\n$description'),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
      ),
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 300),
      showDuration: const Duration(seconds: 8),
      child: child,
    );
  }
}

/// 标题右侧的 ⓘ 标记，提示「这一项有说明」。
/// 不自带 Tooltip —— 外层 [FeatureHelp] 已经包住整行，避免两层提示互相抢焦点。
class HelpBadge extends StatelessWidget {
  const HelpBadge({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 5),
        child: Icon(
          Icons.info_outline_rounded,
          size: size,
          color: AppColors.inkSoft.withValues(alpha: 0.8),
        ),
      );
}

/// 给标题文字接上 ⓘ 标记，供 `SettingRow.title` / `SwitchListTile.title` 使用。
Widget helpTitle(
  String label, {
  double fontSize = 13.5,
  FontWeight fontWeight = FontWeight.w600,
}) =>
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: fontSize, fontWeight: fontWeight)),
        const HelpBadge(),
      ],
    );
