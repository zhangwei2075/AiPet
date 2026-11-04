import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
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
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.2) : null,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: const Color(0xFF8A6A4F).withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = true,
    this.color,
    this.dense = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final Color? color;
  final bool dense;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    final fg = filled ? Colors.white : AppColors.ink;
    return Material(
      color: filled ? accent.withValues(alpha: enabled ? 1 : 0.4) : Colors.white.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 18, vertical: dense ? 7 : 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: filled ? null : Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 14 : 16, color: filled ? fg : accent),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: dense ? 12 : 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 34,
    this.color = Colors.white,
    this.iconColor = AppColors.ink,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: color.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.5, color: iconColor),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          child,
        ],
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.color, this.dense = false});

  final String label;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: dense ? 10.5 : 11.5,
          color: Color.lerp(tint, AppColors.ink, 0.35),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text, this.icon = Icons.pets_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppColors.inkSoft.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// 轻微浮起的白色卡片，用于宠物列表。
class SoftTile extends StatelessWidget {
  const SoftTile({super.key, required this.child, this.onTap, this.selected = false, this.radius = 20});

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? accent.withValues(alpha: 0.75) : AppColors.line.withValues(alpha: 0.8),
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class BlurBackdrop extends StatelessWidget {
  const BlurBackdrop({super.key, required this.child, this.color = const Color(0xEEFFF9F2)});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(color: color, child: child),
      ),
    );
  }
}
