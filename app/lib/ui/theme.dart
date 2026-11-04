import 'package:flutter/material.dart';

class AppColors {
  static const cream = Color(0xFFFDF6EC);
  static const card = Color(0xFFFFFBF5);
  static const ink = Color(0xFF3F2E28);
  static const inkSoft = Color(0xFF8A7568);
  static const line = Color(0xFFEFE2D2);
  static const danger = Color(0xFFD9534F);
}

ThemeData buildAppTheme(Color accent) {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light).copyWith(
    surface: AppColors.card,
    primary: accent,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final textTheme = base.textTheme.apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
    fontFamilyFallback: const ['Microsoft YaHei UI', 'PingFang SC', 'Noto Sans SC'],
  ).copyWith(
    labelLarge: base.textTheme.labelLarge?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      hintStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: accent,
      thumbColor: accent,
      inactiveTrackColor: accent.withValues(alpha: 0.16),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : const Color(0xFFE3D8CB),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 24),
  );
}
