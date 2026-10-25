import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography. English uses Nunito; Arabic & Kurdish use Vazirmatn.
/// Colours here are light-mode defaults; use `.copyWith(color: AppColors.text(context))`
/// (or the theme-aware helpers in AppColors) on dark surfaces.
class AppTextStyles {
  AppTextStyles._();

  static String fontFamily(Locale locale) =>
      (locale.languageCode == 'ar' || locale.languageCode == 'ckb')
          ? 'Vazirmatn'
          : 'Nunito';

  static const TextStyle heading1 = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2);
  static const TextStyle heading2 = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25);
  static const TextStyle heading3 = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.3);
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5);
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.5);
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4);
  static const TextStyle label = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const TextStyle button = TextStyle(
    fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textOnPrimary);
  static const TextStyle price = TextStyle(
    fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.goldTextLight);
  static const TextStyle priceSmall = TextStyle(
    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const TextStyle priceOld = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textHint,
    decoration: TextDecoration.lineThrough);
  static const TextStyle link = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.goldTextLight);
}
