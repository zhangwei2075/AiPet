import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'feature_help.dart';
import 'theme.dart';

/// 卡片：白底 + 一根发丝边，不靠重阴影堆层次。
///
/// 桌宠面板浮在桌面之上，四周已经有窗口阴影了，里面的卡片再叠阴影会很脏。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.x5),
    this.radius = Radii.card,
    this.color = AppColors.surface,
    this.border = true,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final bool border;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: border ? Border.all(color: AppColors.line) : null,
    );
    if (onTap == null) {
      return Container(
          padding: padding,
          clipBehavior: clip ? Clip.antiAlias : Clip.none,
          decoration: decoration,
          child: child);
    }
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// 面板外框。保留旧名字，内部换成「白卡 + 发丝边 + 极淡投影」。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.x5),
    this.radius = Radii.panel,
    this.color,
    this.border = true,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: AppColors.line) : null,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: const Color(0xFF3B2A1C).withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// 主按钮 / 次按钮。同一个组件，靠 [filled] 切换层级。
///
/// 按下去缩小到 0.97、悬停放大到 1.02，只动 transform，
/// 时长 120ms，点到即止 —— 桌宠是长期挂在桌面上的，动效不能吵。
class PillButton extends StatefulWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = true,
    this.color,
    this.dense = false,
    this.enabled = true,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final Color? color;
  final bool dense;
  final bool enabled;

  /// 撑满父级宽度（表单底部的主行动按钮）。
  final bool expand;

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hover = false;
  bool _down = false;

  bool get _active => widget.enabled && widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? Theme.of(context).colorScheme.primary;
    final onAccent = readableOn(accent);

    late final Color bg;
    late final Color fg;
    late final Color? borderColor;
    if (!_active) {
      bg = widget.filled ? AppColors.surfaceSunken : AppColors.surface;
      fg = AppColors.inkFaint;
      borderColor = widget.filled ? null : AppColors.line;
    } else if (widget.filled) {
      bg = _hover ? Color.lerp(accent, AppColors.ink, 0.10)! : accent;
      fg = onAccent;
      borderColor = null;
    } else {
      bg = _hover ? AppColors.surfaceAlt : AppColors.surface;
      fg = AppColors.ink;
      borderColor =
          _hover ? Color.lerp(AppColors.line, accent, 0.35) : AppColors.line;
    }

    final height = widget.dense ? 30.0 : 38.0;
    final fontSize = widget.dense ? 12.0 : 13.0;
    final iconSize = widget.dense ? 14.0 : 15.0;

    return MouseRegion(
      cursor: _active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        // onTap 必须显式挂上：只写 onTapDown/onTapUp 时手势竞技场不会把它
        // 当成一次点击，按钮只有按下去的动效、永远不触发回调。
        behavior: HitTestBehavior.opaque,
        onTap: _active ? widget.onPressed : null,
        onTapDown: _active ? (_) => setState(() => _down = true) : null,
        onTapCancel: _active ? () => setState(() => _down = false) : null,
        onTapUp: _active ? (_) => setState(() => _down = false) : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : (_hover && _active ? 1.02 : 1),
          duration: Motion.fast,
          curve: Motion.curve,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            height: height,
            width: widget.expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.control),
              border:
                  borderColor == null ? null : Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon,
                      size: iconSize,
                      color: widget.filled && _active
                          ? fg
                          : (_active ? accent : fg)),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形图标按钮：工具栏、标题栏右侧用。
/// 触控目标不小于 34，悬停给一层浅底，比裸图标更容易发现。
class RoundIconButton extends StatefulWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 34,
    this.color = Colors.transparent,
    this.iconColor = AppColors.inkSoft,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color color;
  final Color iconColor;

  @override
  State<RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<RoundIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final bg = widget.color == Colors.transparent
        ? (_hover && enabled ? AppColors.surfaceAlt : Colors.transparent)
        : widget.color;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.fast,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            child: Icon(
              widget.icon,
              size: widget.size * 0.5,
              color: enabled ? widget.iconColor : AppColors.inkFaint,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// 分组小标题：设置页、列表分组用。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.description});

  final String text;
  final Widget? trailing;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.x2, top: Insets.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
              letterSpacing: 0.4,
            ),
          ),
          if (description != null) ...[
            const SizedBox(width: Insets.x2),
            Expanded(
              child: Text(
                description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, height: 1.4, color: AppColors.inkFaint),
              ),
            ),
          ] else
            const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 「标题 + 说明 + 右侧控件」的开关行。
///
/// [help] 有值时，整行悬停出 Tooltip、标题带 ⓘ；这是全站功能说明的唯一出口，
/// 保证卡片本身不堆大段解释文字（见 feature_help.dart）。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.help,
    required this.child,
    this.divider = false,
  });

  final String title;
  final String? subtitle;

  /// 功能说明：有值时整行悬停会显示 Tooltip，标题旁带 ⓘ 标记。
  final String? help;

  final Widget child;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (help == null)
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600))
                else
                  helpTitle(title),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkSoft, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Insets.x4),
          // 设置页行高主要被 M3 开关的 40px 撑起来（这个尺寸不看主题密度）。
          // 这里只在行尾是开关时等比缩到 34，行高 59 → 45，一屏多放两行；
          // 滑杆、下拉不缩，否则宽度会被压变形。
          if (child is Switch)
            SizedBox(
              height: 34,
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.centerRight,
                child: child,
              ),
            )
          else
            child,
        ],
      ),
    );
    final withHelp = help == null
        ? row
        : FeatureHelp(label: title, description: help!, child: row);
    if (!divider) return withHelp;
    return Column(children: [withHelp, const Divider(height: 1)]);
  }
}

/// 标签：性格、状态、分类。默认取主题 accent 的淡底。
class TagChip extends StatelessWidget {
  const TagChip(
      {super.key,
      required this.label,
      this.color,
      this.dense = false,
      this.icon});

  final String label;
  final Color? color;
  final bool dense;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 7 : 9, vertical: dense ? 2.5 : 3.5),
      decoration: BoxDecoration(
        color: tintOf(tint, 0.13),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 11, color: inkOn(tint)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11 : 11.5,
              color: inkOn(tint),
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态：一个圆底图标 + 一句说明，不铺大段文案。
class EmptyHint extends StatelessWidget {
  const EmptyHint(
      {super.key, required this.text, this.icon = Icons.pets_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                color: AppColors.surfaceAlt, shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: AppColors.inkFaint),
          ),
          const SizedBox(height: Insets.x3),
          Text(text,
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// 可点卡片的统一外壳：悬停浮起一点，选中用 accent 描边。
class SoftTile extends StatefulWidget {
  const SoftTile({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.radius = Radii.card,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;

  @override
  State<SoftTile> createState() => _SoftTileState();
}

class _SoftTileState extends State<SoftTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final borderColor = widget.selected
        ? accent
        : (_hover ? Color.lerp(AppColors.line, accent, 0.35)! : AppColors.line);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.curve,
        transform: Matrix4.translationValues(
            0, _hover && !widget.selected ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(widget.radius),
          border:
              Border.all(color: borderColor, width: widget.selected ? 1.6 : 1),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.16),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ]
              : (_hover
                  ? [
                      BoxShadow(
                          color:
                              const Color(0xFF3B2A1C).withValues(alpha: 0.07),
                          blurRadius: 14,
                          offset: const Offset(0, 6))
                    ]
                  : null),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: widget.onTap, child: widget.child),
        ),
      ),
    );
  }
}

class BlurBackdrop extends StatelessWidget {
  const BlurBackdrop(
      {super.key, required this.child, this.color = const Color(0xEEF7F4EF)});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.panel),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(color: color, child: child),
      ),
    );
  }
}

/// 页面头部：主标题 + 一句副标题 + 右侧主次按钮。
///
/// 四个 Tab 都走这个组件，标题字号与基线才不会各写一套。
/// 窄窗口（手机面板）下自动改成上下两行，避免按钮把标题挤成竖排。
class AppPageHeader extends StatelessWidget {
  const AppPageHeader(
      {super.key, required this.title, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.displayColor,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12.5, height: 1.4, color: AppColors.inkSoft),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.x4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions == null) return heading;
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: Insets.x3),
                Wrap(
                    spacing: Insets.x2,
                    runSpacing: Insets.x2,
                    children: actions!),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              const SizedBox(width: Insets.x3),
              Wrap(
                  spacing: Insets.x2,
                  runSpacing: Insets.x2,
                  children: actions!),
            ],
          );
        },
      ),
    );
  }
}

/// 表单字段：小标题在上，输入框在下，统一间距。
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft)),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.45, color: AppColors.inkFaint)),
        ],
      ],
    );
  }
}

/// 分段选择：比 Material 的 SegmentedButton 更贴这套圆角语言，
/// 选中项浮起来一层，不靠描边区分。
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.values,
    required this.value,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.dense = false,
  });

  final List<T> values;
  final T value;
  final String Function(T value) labelOf;
  final IconData? Function(T value)? iconOf;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.control)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in values)
            _segment(context, item, item == value, accent),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, T item, bool selected, Color accent) {
    final icon = iconOf?.call(item);
    return GestureDetector(
      onTap: () => onChanged(item),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.curve,
        height: dense ? 28 : 34,
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.sm),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: const Color(0xFF3B2A1C).withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: dense ? 13 : 14,
                  color: selected ? accent : AppColors.inkFaint),
              const SizedBox(width: 5),
            ],
            Text(
              labelOf(item),
              style: TextStyle(
                fontSize: dense ? 12 : 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BannerTone { info, success, warning, danger }

/// 状态条：在线/离线、错误提示、生成提示。
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.text,
    this.tone = BannerTone.info,
    this.icon,
    this.action,
  });

  final String text;
  final BannerTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, defaultIcon) = switch (tone) {
      BannerTone.info => (
          AppColors.surfaceAlt,
          AppColors.inkSoft,
          Icons.info_outline_rounded
        ),
      BannerTone.success => (
          AppColors.successTint,
          AppColors.success,
          Icons.check_circle_rounded
        ),
      BannerTone.warning => (
          AppColors.warningTint,
          AppColors.warning,
          Icons.warning_amber_rounded
        ),
      BannerTone.danger => (
          AppColors.dangerTint,
          AppColors.danger,
          Icons.error_outline_rounded
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.x3, vertical: 10),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(Radii.control)),
      child: Row(
        children: [
          Icon(icon ?? defaultIcon, size: 15, color: fg),
          const SizedBox(width: Insets.x2),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, height: 1.45, color: fg)),
          ),
          if (action != null) ...[const SizedBox(width: Insets.x2), action!],
        ],
      ),
    );
  }
}

/// 虚线圆角边框：照片生成的拖放区。
class DashedBorderPainter extends CustomPainter {
  DashedBorderPainter(
      {required this.color,
      this.radius = Radii.card,
      this.dash = 5,
      this.gap = 4});

  final Color color;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// 虚线边框容器。
class DashedBox extends StatelessWidget {
  const DashedBox(
      {super.key,
      required this.child,
      this.color = AppColors.line,
      this.radius = Radii.card,
      this.background});

  final Widget child;
  final Color color;
  final double radius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DashedBorderPainter(color: color, radius: radius),
      child: Container(
        decoration: BoxDecoration(
          color: background ?? AppColors.surface,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}
