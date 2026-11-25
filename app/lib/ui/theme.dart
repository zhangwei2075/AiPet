import 'package:flutter/material.dart';

/// 设计令牌（Design Tokens）。
///
/// 界面里所有颜色、间距、圆角、字号都从这里取，不要在页面里再写
/// `Color(0xFF...)`、`SizedBox(height: 7)`、`fontSize: 10.5` 这类一次性常量。
/// 改一处就能全站生效，也是「看起来像同一套界面」的前提。
abstract final class AppColors {
  /// 窗口内底色：暖白，比纯白柔和，深色桌面下也不刺眼。
  static const canvas = Color(0xFFF7F4EF);

  /// 卡片 / 面板底色。
  static const surface = Color(0xFFFFFFFF);

  /// 次级面（输入框、内嵌区块、未选中的分段）。
  static const surfaceAlt = Color(0xFFF5F1EA);

  /// 仅用于需要更强区分的嵌套块（列表 hover 等）。
  static const surfaceSunken = Color(0xFFEFEAE1);

  static const ink = Color(0xFF26211D);
  static const inkSoft = Color(0xFF6C6159);
  static const inkFaint = Color(0xFF786E66);

  static const line = Color(0xFFE8E1D6);
  static const lineSoft = Color(0xFFF1ECE3);

  static const danger = Color(0xFFC4443C);
  static const dangerTint = Color(0xFFFCEEEC);
  static const success = Color(0xFF2F7D53);
  static const successTint = Color(0xFFECF6F0);
  static const warning = Color(0xFF8F6417);
  static const warningTint = Color(0xFFFBF3E3);

  // ── 旧名兼容（历史代码仍在引用）────────────────────────────────
  static const cream = canvas;
  static const card = surface;
}

/// 间距：4 的倍数。页面外边距 20，卡片内边距 20，元素间距 12 / 8。
abstract final class Insets {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

/// 圆角：控件 12，卡片 16，面板 24，胶囊 999。
abstract final class Radii {
  static const xs = 8.0;
  static const sm = 10.0;
  static const control = 12.0;
  static const card = 16.0;
  static const panel = 24.0;
  static const pill = 999.0;
}

/// 动效时长：只动画 transform / opacity，控制在 0.3s 内。
abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
}

/// 字号刻度：22 / 17 / 15 / 13.5 / 12.5 / 11.5，字重只用 w500 / w600 / w700。
/// 刻意不提供 10px 以下的字：桌宠面板本来就在小屏上，再缩就不可读了。
abstract final class AppType {
  static const display = TextStyle(
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3);
  static const title = TextStyle(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1);
  static const subtitle =
      TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600);
  static const body =
      TextStyle(fontSize: 13.5, height: 1.55, fontWeight: FontWeight.w400);
  static const bodyStrong =
      TextStyle(fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w600);
  static const label =
      TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600);
  static const meta =
      TextStyle(fontSize: 11.5, height: 1.45, fontWeight: FontWeight.w500);
  static const overline = TextStyle(
      fontSize: 11.5,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6);

  static const displayColor = TextStyle(
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: AppColors.ink);
  static const titleColor = TextStyle(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: AppColors.ink);
  static const bodyColor =
      TextStyle(fontSize: 13.5, height: 1.55, color: AppColors.ink);
  static const metaColor =
      TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.inkSoft);
}

/// 背景色上的可读前景色。
///
/// 每只宠物自带 accent（黄狗、薄荷猫、芋圆……），亮度差别很大：白字压在浅橙上
/// 只有 2:1 出头，压在深紫上又过呛。这里按相对亮度直接算两种对比度取高的那个，
/// 保证正文至少 4.5:1（WCAG 2.2 AA）。
Color readableOn(Color background) {
  final l = background.computeLuminance();
  final onWhite = 1.05 / (l + 0.05);
  final onInk = (l + 0.05) / (AppColors.ink.computeLuminance() + 0.05);
  return onInk >= onWhite ? AppColors.ink : Colors.white;
}

/// 把 accent 压成可做背景的浅色块。
Color tintOf(Color color, [double alpha = 0.12]) =>
    color.withValues(alpha: alpha);

/// 让 accent 在浅底上做文字时足够深（用于链接、选中文字）。
Color inkOn(Color color) => Color.lerp(color, AppColors.ink, 0.42)!;

ThemeData buildAppTheme(Color accent) {
  final onAccent = readableOn(accent);
  final scheme =
      ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light)
          .copyWith(
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: tintOf(accent, 0.14),
    onPrimaryContainer: AppColors.ink,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSoft,
    surfaceContainerHighest: AppColors.surfaceAlt,
    outline: AppColors.line,
    outlineVariant: AppColors.lineSoft,
    error: AppColors.danger,
    onError: Colors.white,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final fontFallback = const [
    'Microsoft YaHei UI',
    'PingFang SC',
    'Noto Sans SC',
    'Segoe UI'
  ];
  TextStyle text(double size, FontWeight weight,
          {Color color = AppColors.ink,
          double height = 1.5,
          double spacing = 0}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
        fontFamilyFallback: fontFallback,
      );

  final textTheme = base.textTheme
      .copyWith(
        displaySmall: text(22, FontWeight.w700, height: 1.25, spacing: -0.3),
        headlineSmall: text(17, FontWeight.w700, height: 1.3),
        titleLarge: text(17, FontWeight.w700, height: 1.3),
        titleMedium: text(15, FontWeight.w600, height: 1.35),
        titleSmall: text(13.5, FontWeight.w600, height: 1.4),
        bodyLarge: text(14, FontWeight.w400),
        bodyMedium: text(13.5, FontWeight.w400),
        bodySmall:
            text(12, FontWeight.w400, color: AppColors.inkSoft, height: 1.45),
        labelLarge: text(13, FontWeight.w600, height: 1.3),
        labelMedium: text(12, FontWeight.w600, height: 1.3),
        labelSmall:
            text(11.5, FontWeight.w500, color: AppColors.inkSoft, height: 1.3),
      )
      .apply(
          bodyColor: AppColors.ink,
          displayColor: AppColors.ink,
          fontFamilyFallback: fontFallback);

  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    // 桌宠窗口本身要透明，整页导航会显式铺 canvas。
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: AppColors.surface,
    // 键盘用户的焦点必须可见：InkWell 默认用这套颜色画焦点层。
    hoverColor: AppColors.surfaceAlt,
    focusColor: tintOf(accent, 0.18),
    highlightColor: tintOf(accent, 0.10),
    textTheme: textTheme,
    iconTheme: const IconThemeData(size: 18, color: AppColors.inkSoft),
    primaryIconTheme: IconThemeData(color: onAccent),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      isDense: true,
      hintStyle:
          text(13, FontWeight.w400, color: AppColors.inkFaint, height: 1.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(accent, 1.5),
      disabledBorder: border(Colors.transparent, 0),
      errorBorder: border(AppColors.danger, 1.2),
      errorStyle:
          text(11.5, FontWeight.w500, color: AppColors.danger, height: 1.3),
    ),

    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: accent,
      thumbColor: accent,
      inactiveTrackColor: AppColors.surfaceSunken,
      trackHeight: 4,
      tickMarkShape: SliderTickMarkShape.noTickMark,
      thumbShape:
          const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 1.5),
      overlayShape: SliderComponentShape.noOverlay,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : AppColors.surfaceSunken,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      // 不留额外留白：开关本身 32 高，多出来的内边距会把设置行顶到 59px。
      padding: EdgeInsets.zero,
    ),

    dividerTheme: const DividerThemeData(
        color: AppColors.lineSoft, thickness: 1, space: 1),

    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.line),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.panel)),
      insetPadding: const EdgeInsets.all(Insets.x6),
      titleTextStyle: AppType.titleColor,
      contentTextStyle: const TextStyle(
          fontSize: 13.5, height: 1.6, color: AppColors.inkSoft),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.line),
      ),
      textStyle: const TextStyle(fontSize: 13, color: AppColors.ink),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      textStyle:
          const TextStyle(fontSize: 12, height: 1.5, color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      waitDuration: const Duration(milliseconds: 400),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(fontSize: 12.5, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      insetPadding: const EdgeInsets.all(Insets.x4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control)),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.sm)),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        minimumSize: const Size(0, 38),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control)),
      ),
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 10,
      titleTextStyle: const TextStyle(
          fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink),
      subtitleTextStyle:
          const TextStyle(fontSize: 12, height: 1.45, color: AppColors.inkSoft),
      iconColor: AppColors.inkSoft,
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? tintOf(accent, 0.16)
              : AppColors.surface,
        ),
        foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        ),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: tintOf(accent, 0.14),
      circularTrackColor: AppColors.lineSoft,
      linearMinHeight: 5,
    ),

    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(999),
      thumbColor:
          WidgetStatePropertyAll(AppColors.inkFaint.withValues(alpha: 0.35)),
      crossAxisMargin: 2,
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: const TextStyle(fontSize: 13, color: AppColors.ink),
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(12),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card))),
      ),
    ),
  );
}
