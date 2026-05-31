import 'dart:ui';

import 'package:flutter/material.dart';
import 'app_constants.dart';

/// Дизайн-система приложения — industrial-grade, SOTA 2026.
///
/// Палитра «Graphite + Cyan»: спокойный графит как primary (авторитет/контекст
/// цеха), глубокий cyan как secondary (один яркий акцент для CTA/важных
/// состояний), forest-green tertiary (успех/выполнено), индустриально-красный
/// error. Поверхности — тёплый off-white вместо стерильно-белого: дольше
/// читается и не «жжёт» глаза.
///
/// Принципы:
///   • tonal elevation вместо теней (Material 3) — глубина через ступени
///     surfaceContainerLow→Highest, тени только для модалок/FAB;
///   • AAA-контраст для текста на любых поверхностях;
///   • тап-таргеты ≥ 48px (≥ 56px для primary CTA — перчатки);
///   • tabular figures для счётчиков/времени, чтобы числа «не прыгали»;
///   • радиусы по шкале 8/12/16/24/28 (M3 Expressive: модалки крупно).
class AppTheme {
  AppTheme._();

  // ───────────────────────────────────────────────────────────
  // Публичные точки входа
  // ───────────────────────────────────────────────────────────

  static ThemeData get lightTheme => _build(lightScheme(), Brightness.light);
  static ThemeData get darkTheme => _build(darkScheme(), Brightness.dark);

  // Совместимость со старыми названиями (если где-то ссылались)
  static ThemeData get lightMediumContrast => lightTheme;
  static ThemeData get lightHighContrast => lightTheme;
  static ThemeData get darkMediumContrast => darkTheme;
  static ThemeData get darkHighContrast => darkTheme;

  // ───────────────────────────────────────────────────────────
  // Цветовые схемы — Graphite + Cyan
  // ───────────────────────────────────────────────────────────

  /// Светлая схема. Тёплые off-white поверхности, графитовый primary,
  /// cyan для акцентов, emerald для успеха.
  static ColorScheme lightScheme() => const ColorScheme.light(
        // Brand
        primary: Color(0xFF1A2332),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFDDE5EE),
        onPrimaryContainer: Color(0xFF0E1620),

        // Accent (cyan)
        secondary: Color(0xFF0891B2),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFCFFAFE),
        onSecondaryContainer: Color(0xFF164E63),

        // Success (forest green)
        tertiary: Color(0xFF047857),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFD1FAE5),
        onTertiaryContainer: Color(0xFF064E3B),

        // Error
        error: Color(0xFFDC2626),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFEE2E2),
        onErrorContainer: Color(0xFF7F1D1D),

        // Surfaces (warm paper-like)
        surface: Color(0xFFFAFAF9),
        onSurface: Color(0xFF1A2332),
        onSurfaceVariant: Color(0xFF4B5563),
        surfaceContainerLowest: Color(0xFFFFFFFF),
        surfaceContainerLow: Color(0xFFF7F7F5),
        surfaceContainer: Color(0xFFF1F1EE),
        surfaceContainerHigh: Color(0xFFE9E9E5),
        surfaceContainerHighest: Color(0xFFDCDCD7),

        // Outlines
        outline: Color(0xFF9CA3AF),
        outlineVariant: Color(0xFFE1E4E8),

        // System
        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),

        // Inverse (для тёмных полос: status bar, scanner, snackbar и пр.)
        inverseSurface: Color(0xFF1A2332),
        onInverseSurface: Color(0xFFFAFAF9),
        inversePrimary: Color(0xFF22D3EE),

        surfaceTint: Color(0xFF1A2332),
      );

  /// Тёмная схема. На случай если когда-нибудь включим dark mode.
  /// Inverted поверхности, тот же cyan-акцент.
  static ColorScheme darkScheme() => const ColorScheme.dark(
        primary: Color(0xFF22D3EE),
        onPrimary: Color(0xFF0E1620),
        primaryContainer: Color(0xFF1F3247),
        onPrimaryContainer: Color(0xFFCFFAFE),

        secondary: Color(0xFF22D3EE),
        onSecondary: Color(0xFF0E1620),
        secondaryContainer: Color(0xFF164E63),
        onSecondaryContainer: Color(0xFFCFFAFE),

        tertiary: Color(0xFF34D399),
        onTertiary: Color(0xFF064E3B),
        tertiaryContainer: Color(0xFF065F46),
        onTertiaryContainer: Color(0xFFD1FAE5),

        error: Color(0xFFFCA5A5),
        onError: Color(0xFF7F1D1D),
        errorContainer: Color(0xFF991B1B),
        onErrorContainer: Color(0xFFFEE2E2),

        surface: Color(0xFF0F1620),
        onSurface: Color(0xFFE7E9EC),
        onSurfaceVariant: Color(0xFFB0B6BD),
        surfaceContainerLowest: Color(0xFF0A0F16),
        surfaceContainerLow: Color(0xFF131B26),
        surfaceContainer: Color(0xFF17202C),
        surfaceContainerHigh: Color(0xFF1E2734),
        surfaceContainerHighest: Color(0xFF26313E),

        outline: Color(0xFF6B7280),
        outlineVariant: Color(0xFF374151),

        shadow: Color(0xFF000000),
        scrim: Color(0xFF000000),

        inverseSurface: Color(0xFFFAFAF9),
        onInverseSurface: Color(0xFF1A2332),
        inversePrimary: Color(0xFF1A2332),

        surfaceTint: Color(0xFF22D3EE),
      );

  /// Совместимость со старым API (внешние использования)
  static ColorScheme lightMediumContrastScheme() => lightScheme();
  static ColorScheme lightHighContrastScheme() => lightScheme();
  static ColorScheme darkMediumContrastScheme() => darkScheme();
  static ColorScheme darkHighContrastScheme() => darkScheme();
  static ThemeData theme(ColorScheme colorScheme) =>
      _build(colorScheme, colorScheme.brightness);

  // ───────────────────────────────────────────────────────────
  // Сборка темы
  // ───────────────────────────────────────────────────────────

  static ThemeData _build(ColorScheme cs, Brightness brightness) {
    final tt = _textTheme(cs);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,

      textTheme: tt,
      primaryTextTheme: tt,

      appBarTheme: _appBarTheme(cs, tt),
      bottomAppBarTheme: BottomAppBarTheme(
        color: cs.surfaceContainerLow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // Buttons
      elevatedButtonTheme: _elevatedButtonTheme(cs, tt),
      filledButtonTheme: _filledButtonTheme(cs, tt),
      outlinedButtonTheme: _outlinedButtonTheme(cs, tt),
      textButtonTheme: _textButtonTheme(cs, tt),
      iconButtonTheme: _iconButtonTheme(cs),
      floatingActionButtonTheme: _fabTheme(cs),

      // Surfaces / containers
      cardTheme: _cardTheme(cs),
      dialogTheme: _dialogTheme(cs, tt),
      bottomSheetTheme: _bottomSheetTheme(cs),
      popupMenuTheme: _popupMenuTheme(cs, tt),
      navigationBarTheme: _navigationBarTheme(cs, tt),
      bottomNavigationBarTheme: _bottomNavigationBarTheme(cs, tt),

      // Inputs & lists
      inputDecorationTheme: _inputDecorationTheme(cs, tt),
      listTileTheme: _listTileTheme(cs, tt),
      chipTheme: _chipTheme(cs, tt),
      switchTheme: _switchTheme(cs),
      checkboxTheme: _checkboxTheme(cs),
      radioTheme: _radioTheme(cs),
      sliderTheme: _sliderTheme(cs),
      dividerTheme: _dividerTheme(cs),
      tabBarTheme: _tabBarTheme(cs, tt),

      // Feedback
      snackBarTheme: _snackBarTheme(cs, tt),
      progressIndicatorTheme: _progressIndicatorTheme(cs),
      tooltipTheme: _tooltipTheme(cs, tt),

      // Icons
      iconTheme: IconThemeData(color: cs.onSurface, size: 24),
      primaryIconTheme: IconThemeData(color: cs.onPrimary, size: 24),
    );
  }

  // ───────────────────────────────────────────────────────────
  // Типографика — utility scale + tabular numerics для счётчиков
  // ───────────────────────────────────────────────────────────

  static TextTheme _textTheme(ColorScheme cs) {
    const tabular = [FontFeature.tabularFigures()];
    return TextTheme(
      // Display — крупная reklama, редко
      displayLarge: TextStyle(
        fontSize: AppConstants.fontSizeDisplayLarge,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
        height: 1.12,
        color: cs.onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: AppConstants.fontSizeDisplayMedium,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.25,
        height: 1.16,
        color: cs.onSurface,
      ),
      displaySmall: TextStyle(
        fontSize: AppConstants.fontSizeDisplaySmall,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.22,
        color: cs.onSurface,
      ),

      // Headline — заголовки экранов/секций
      headlineLarge: TextStyle(
        fontSize: AppConstants.fontSizeHeadlineLarge,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        height: 1.2,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: AppConstants.fontSizeHeadlineMedium,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.22,
        color: cs.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: AppConstants.fontSizeHeadlineSmall,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.28,
        color: cs.onSurface,
      ),

      // Title — заголовки карточек/диалогов, кнопки
      titleLarge: TextStyle(
        fontSize: AppConstants.fontSizeTitleLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.27,
        fontFeatures: tabular,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: AppConstants.fontSizeTitleMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        height: 1.5,
        fontFeatures: tabular,
        color: cs.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: AppConstants.fontSizeTitleSmall,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.43,
        fontFeatures: tabular,
        color: cs.onSurface,
      ),

      // Body — основной текст
      bodyLarge: TextStyle(
        fontSize: AppConstants.fontSizeBodyLarge,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
        height: 1.5,
        color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: AppConstants.fontSizeBodyMedium,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.15,
        height: 1.43,
        color: cs.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: AppConstants.fontSizeBodySmall,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        height: 1.33,
        color: cs.onSurfaceVariant,
      ),

      // Label — кнопки, бейджи, метки (tabular для счётчиков)
      labelLarge: TextStyle(
        fontSize: AppConstants.fontSizeLabelLarge,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.43,
        fontFeatures: tabular,
        color: cs.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: AppConstants.fontSizeLabelMedium,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.33,
        fontFeatures: tabular,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontSize: AppConstants.fontSizeLabelSmall,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.45,
        fontFeatures: tabular,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // Sub-themes
  // ───────────────────────────────────────────────────────────

  static AppBarTheme _appBarTheme(ColorScheme cs, TextTheme tt) => AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppConstants.spacingMD,
        toolbarHeight: 56,
        iconTheme: IconThemeData(color: cs.onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: cs.onSurface, size: 24),
        titleTextStyle: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        shape: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      );

  /// Primary CTA (Filled-style на ElevatedButton — большинство старых вызовов)
  static ElevatedButtonThemeData _elevatedButtonTheme(
          ColorScheme cs, TextTheme tt) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLG,
            vertical: AppConstants.spacingSM + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          textStyle: tt.labelLarge,
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(
          ColorScheme cs, TextTheme tt) =>
      FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLG,
            vertical: AppConstants.spacingSM + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          textStyle: tt.labelLarge,
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(
          ColorScheme cs, TextTheme tt) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingLG,
            vertical: AppConstants.spacingSM + 4,
          ),
          side: BorderSide(color: cs.outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
          textStyle: tt.labelLarge,
        ),
      );

  static TextButtonThemeData _textButtonTheme(
          ColorScheme cs, TextTheme tt) =>
      TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMD,
            vertical: AppConstants.spacingSM,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          ),
          textStyle: tt.labelLarge,
        ),
      );

  static IconButtonThemeData _iconButtonTheme(ColorScheme cs) =>
      IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          minimumSize: const Size(40, 40),
        ),
      );

  static FloatingActionButtonThemeData _fabTheme(ColorScheme cs) =>
      FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 3,
        focusElevation: 4,
        hoverElevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        ),
      );

  /// Карточки — без теней, tonal background, чёткие края.
  static CardThemeData _cardTheme(ColorScheme cs) => CardThemeData(
        color: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
          side: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      );

  static DialogThemeData _dialogTheme(ColorScheme cs, TextTheme tt) =>
      DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        ),
        titleTextStyle: tt.headlineSmall,
        contentTextStyle: tt.bodyMedium,
      );

  static BottomSheetThemeData _bottomSheetTheme(ColorScheme cs) =>
      BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cs.surface,
        modalElevation: 0,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: cs.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
        ),
      );

  static PopupMenuThemeData _popupMenuTheme(ColorScheme cs, TextTheme tt) =>
      PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        ),
        textStyle: tt.bodyMedium,
      );

  static NavigationBarThemeData _navigationBarTheme(
          ColorScheme cs, TextTheme tt) =>
      NavigationBarThemeData(
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tt.labelMedium?.copyWith(color: cs.onSurface);
          }
          return tt.labelMedium?.copyWith(color: cs.onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.onSecondaryContainer);
          }
          return IconThemeData(color: cs.onSurfaceVariant);
        }),
        height: 72,
        elevation: 0,
      );

  static BottomNavigationBarThemeData _bottomNavigationBarTheme(
          ColorScheme cs, TextTheme tt) =>
      BottomNavigationBarThemeData(
        backgroundColor: cs.surface,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        selectedLabelStyle: tt.labelSmall?.copyWith(color: cs.primary),
        unselectedLabelStyle: tt.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      );

  static InputDecorationTheme _inputDecorationTheme(
      ColorScheme cs, TextTheme tt) {
    OutlineInputBorder border({Color? color, double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          borderSide: BorderSide(color: color ?? cs.outline, width: width),
        );
    return InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMD,
        vertical: AppConstants.spacingSM + 6,
      ),
      isDense: false,
      hintStyle: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      labelStyle: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      floatingLabelStyle: tt.bodySmall?.copyWith(color: cs.primary),
      helperStyle: tt.bodySmall,
      errorStyle: tt.bodySmall?.copyWith(color: cs.error),
      border: border(),
      enabledBorder: border(color: cs.outlineVariant),
      focusedBorder: border(color: cs.primary, width: 2),
      errorBorder: border(color: cs.error),
      focusedErrorBorder: border(color: cs.error, width: 2),
      disabledBorder: border(color: cs.outlineVariant),
    );
  }

  static ListTileThemeData _listTileTheme(ColorScheme cs, TextTheme tt) =>
      ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
          vertical: AppConstants.spacingSM / 2,
        ),
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
        titleTextStyle: tt.bodyLarge,
        subtitleTextStyle: tt.bodySmall,
        leadingAndTrailingTextStyle: tt.labelMedium,
        minVerticalPadding: AppConstants.spacingSM,
      );

  /// Chip — утилитарный, не pill (8px радиус). С чётким outline.
  static ChipThemeData _chipTheme(ColorScheme cs, TextTheme tt) =>
      ChipThemeData(
        backgroundColor: cs.surfaceContainerLow,
        selectedColor: cs.primary,
        disabledColor: cs.onSurface.withValues(alpha: 0.08),
        secondarySelectedColor: cs.secondaryContainer,
        labelStyle: tt.labelLarge?.copyWith(color: cs.onSurface),
        secondaryLabelStyle: tt.labelLarge?.copyWith(color: cs.onPrimary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD - 2,
          vertical: AppConstants.spacingSM,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusSM),
          side: BorderSide(color: cs.outlineVariant),
        ),
        iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 18),
      );

  static SwitchThemeData _switchTheme(ColorScheme cs) => SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return cs.onSurface.withValues(alpha: 0.38);
          if (states.contains(WidgetState.selected)) return cs.onPrimary;
          return cs.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return cs.onSurface.withValues(alpha: 0.12);
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return cs.outline;
        }),
      );

  static CheckboxThemeData _checkboxTheme(ColorScheme cs) => CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(cs.onPrimary),
        side: BorderSide(color: cs.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusXS),
        ),
      );

  static RadioThemeData _radioTheme(ColorScheme cs) => RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.outline;
        }),
      );

  static SliderThemeData _sliderTheme(ColorScheme cs) => SliderThemeData(
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withValues(alpha: 0.12),
      );

  static DividerThemeData _dividerTheme(ColorScheme cs) => DividerThemeData(
        color: cs.outlineVariant,
        thickness: 0.5,
        space: 1,
      );

  static TabBarThemeData _tabBarTheme(ColorScheme cs, TextTheme tt) =>
      TabBarThemeData(
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: tt.titleSmall,
        unselectedLabelStyle: tt.titleSmall,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: cs.outlineVariant,
        labelPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMD,
        ),
      );

  /// Floating snackbar: inverse surface (тёмная) + контрастный текст.
  static SnackBarThemeData _snackBarTheme(ColorScheme cs, TextTheme tt) =>
      SnackBarThemeData(
        backgroundColor: cs.inverseSurface,
        contentTextStyle: tt.bodyMedium?.copyWith(color: cs.onInverseSurface),
        actionTextColor: cs.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        insetPadding: const EdgeInsets.all(AppConstants.spacingMD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMD),
        ),
      );

  static ProgressIndicatorThemeData _progressIndicatorTheme(ColorScheme cs) =>
      ProgressIndicatorThemeData(
        color: cs.primary,
        circularTrackColor: cs.surfaceContainerHigh,
        linearTrackColor: cs.surfaceContainerHigh,
        linearMinHeight: 4,
      );

  static TooltipThemeData _tooltipTheme(ColorScheme cs, TextTheme tt) =>
      TooltipThemeData(
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(AppConstants.radiusSM),
        ),
        textStyle: tt.bodySmall?.copyWith(color: cs.onInverseSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingSM + 2,
          vertical: AppConstants.spacingSM / 2,
        ),
      );
}

/// Семантические цвета поверх ColorScheme — для специфичных индустриальных
/// статусов, которые не маппятся 1-в-1 на стандартные роли темы.
extension AppSemanticColors on ColorScheme {
  /// Успех / выполнено (= tertiary).
  Color get success => tertiary;
  Color get onSuccess => onTertiary;
  Color get successContainer => tertiaryContainer;
  Color get onSuccessContainer => onTertiaryContainer;

  /// Предупреждение / просрочка скоро.
  Color get warning => const Color(0xFFEA580C);
  Color get onWarning => const Color(0xFFFFFFFF);
  Color get warningContainer => const Color(0xFFFEDD9C);
  Color get onWarningContainer => const Color(0xFF7C2D12);

  /// Информация (нейтральные подсказки).
  Color get info => secondary;
  Color get onInfo => onSecondary;
  Color get infoContainer => secondaryContainer;
  Color get onInfoContainer => onSecondaryContainer;

  /// Приоритеты задач — единая семантика для всех badge.
  Color get priorityHigh => error;
  Color get priorityMedium => const Color(0xFFEA580C);
  Color get priorityLow => tertiary;
}
