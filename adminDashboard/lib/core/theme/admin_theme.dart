import 'package:flutter/material.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';

/// Dashboard theme: the app's gold tokens on a denser desktop layout
/// (light = gold on white, dark = gold on black; SRS §2.2 "light + dark, gold accent").
class AdminTheme {
  AdminTheme._();

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.error,
          onPrimary: AppColors.textOnPrimary,
          onSurface: AppColors.textPrimary,
        ),
        background: AppColors.background,
        line: AppColors.border,
        field: AppColors.surfaceSecondary,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.primary,
          surface: AppColors.darkSurface,
          error: AppColors.error,
          onPrimary: AppColors.textOnPrimary,
          onSurface: AppColors.darkTextPrimary,
        ),
        background: AppColors.darkBackground,
        line: AppColors.darkBorder,
        field: AppColors.darkSurfaceSecondary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required Color line,
    required Color field,
  }) {
    final radius = BorderRadius.circular(AppRadius.sm);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.compact,
      dividerColor: line,
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: line)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        isDense: true,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: brightness == Brightness.light ? AppColors.primarySoft : AppColors.primarySoftDark,
      ),
    );
  }
}
