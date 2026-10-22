import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'dimensions.dart';
import 'text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => forMode(true);
  static ThemeData get light => forMode(false);

  /// يبني الثيم للوضع المطلوب (ويضبط [AppColors.isDark] ليتوافق مع باقي الواجهة).
  static ThemeData forMode(bool isDark) {
    AppColors.isDark = isDark;
    final scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Color(0xFF04222A),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.border,
    );

    final radius = BorderRadius.circular(Dimensions.radiusM);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppFonts.tajawal,
      dividerColor: AppColors.divider,
      textTheme: TextTheme(
        displayLarge: AppTextStyles.display(),
        headlineLarge: AppTextStyles.heading1(),
        headlineMedium: AppTextStyles.heading2(),
        titleLarge: AppTextStyles.heading2(),
        titleMedium: AppTextStyles.heading3(),
        titleSmall: AppTextStyles.label(AppColors.textPrimary),
        bodyLarge: AppTextStyles.bodyLarge(),
        bodyMedium: AppTextStyles.bodyMedium(),
        bodySmall: AppTextStyles.bodySmall(),
        labelLarge: AppTextStyles.button(),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTextStyles.heading2(),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.radiusL),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.radiusL),
          side: BorderSide(color: AppColors.border),
        ),
        titleTextStyle: AppTextStyles.heading2(),
        contentTextStyle: AppTextStyles.bodyLarge(AppColors.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: AppTextStyles.bodyMedium(AppColors.textSecondary),
        hintStyle: AppTextStyles.bodyMedium(AppColors.textMuted),
        errorStyle: AppTextStyles.bodySmall(AppColors.danger),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.primary, 2),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger, 2),
        disabledBorder: inputBorder(AppColors.divider),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: AppTextStyles.button(),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: AppTextStyles.button(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: AppTextStyles.button(AppColors.textPrimary),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: AppTextStyles.button(AppColors.primaryLight),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      // الأزرار المقسّمة (التبويبات الكبيرة): المحدد بنفس لغة الشريط الجانبي
      // (خلفية بنفسجية شفافة + حد بنفسجي + نص واضح) بدل التعبئة السماوية الصارخة.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? AppColors.primary.withValues(alpha: isDark ? 0.24 : 0.16)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? (isDark ? AppColors.textPrimary : AppColors.primaryLight)
                : AppColors.textSecondary,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.border,
            ),
          ),
          overlayColor: WidgetStateProperty.all(
              AppColors.primary.withValues(alpha: 0.10)),
          textStyle: WidgetStateProperty.all(AppTextStyles.button()),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        side: BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: AppTextStyles.label(AppColors.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surfaceHighest,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: AppTextStyles.bodySmall(AppColors.textPrimary),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHighest,
        contentTextStyle: AppTextStyles.bodyMedium(),
        shape: RoundedRectangleBorder(borderRadius: radius),
        width: 520,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: AppColors.border),
        ),
        textStyle: AppTextStyles.bodyMedium(),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.surfaceHighest),
        radius: const Radius.circular(8),
      ),
      listTileTheme: ListTileThemeData(iconColor: AppColors.textSecondary),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.radiusL),
        ),
      ),
    );
  }
}
