import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppFonts {
  AppFonts._();
  static const String cairo = 'Cairo'; // العناوين والأرقام الكبيرة
  static const String tajawal = 'Tajawal'; // النصوص
}

class AppTextStyles {
  AppTextStyles._();

  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle display([Color? color]) => TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        height: 1.2,
        fontFeatures: _tabular,
      );

  static TextStyle heading1([Color? color]) => TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle heading2([Color? color]) => TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle heading3([Color? color]) => TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle bodyLarge([Color? color]) => TextStyle(
        fontFamily: AppFonts.tajawal,
        fontSize: 16,
        color: color ?? AppColors.textPrimary,
        height: 1.5,
      );

  static TextStyle bodyMedium([Color? color]) => TextStyle(
        fontFamily: AppFonts.tajawal,
        fontSize: 14,
        color: color ?? AppColors.textPrimary,
        height: 1.5,
      );

  static TextStyle bodySmall([Color? color]) => TextStyle(
        fontFamily: AppFonts.tajawal,
        fontSize: 12,
        color: color ?? AppColors.textSecondary,
        height: 1.4,
      );

  static TextStyle label([Color? color]) => TextStyle(
        fontFamily: AppFonts.tajawal,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textSecondary,
        height: 1.3,
      );

  static TextStyle button([Color color = Colors.white]) => TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// أرقام العدّاد والمبالغ (أرقام متساوية العرض حتى لا "تهتز" أثناء العدّ).
  static TextStyle timer([Color? color, double size = 28]) =>
      TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        height: 1.1,
        fontFeatures: _tabular,
      );

  static TextStyle price([Color? color, double size = 18]) =>
      TextStyle(
        fontFamily: AppFonts.cairo,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        fontFeatures: _tabular,
      );
}
