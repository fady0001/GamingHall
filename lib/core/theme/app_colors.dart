import 'package:flutter/material.dart';

import '../../features/resources/domain/entities/resource_status.dart';

/// لوحة ألوان "Gaming": خلفية ليلية عميقة مع ألوان نيون للحالات والتمييز.
class AppColors {
  AppColors._();

  /// الوضع الحالي. يضبطه ThemeCubit قبل بناء الواجهة.
  static bool isDark = true;

  // الخلفيات (تتغير حسب الوضع)
  static Color get background => isDark ? const Color(0xFF0A0C16) : const Color(0xFFF3F4FB);
  static Color get surface => isDark ? const Color(0xFF12162A) : const Color(0xFFFFFFFF);
  static Color get surfaceHigh => isDark ? const Color(0xFF1A2040) : const Color(0xFFEBEDF8);
  static Color get surfaceHighest => isDark ? const Color(0xFF232A52) : const Color(0xFFDDE1F2);
  static Color get border => isDark ? const Color(0xFF2B3361) : const Color(0xFFCBD0E6);
  static Color get divider => isDark ? const Color(0xFF1F2648) : const Color(0xFFDDE0F0);

  // ألوان العلامة
  static const Color primary = Color(0xFF7C5CFF); // بنفسجي نيون
  static Color get primaryLight => isDark ? const Color(0xFFA48BFF) : const Color(0xFF5B3FE0);
  static const Color secondary = Color(0xFF22D3EE); // سماوي نيون
  static const Color accent = Color(0xFFF472B6); // وردي نيون

  // النصوص (تتغير حسب الوضع)
  static Color get textPrimary => isDark ? const Color(0xFFF1F3FF) : const Color(0xFF14172B);
  static Color get textSecondary => isDark ? const Color(0xFFA6AEDA) : const Color(0xFF4A5075);
  static Color get textMuted => isDark ? const Color(0xFF6E769F) : const Color(0xFF7A81A6);

  // دلالات
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFB4F6F);
  static const Color info = Color(0xFF38BDF8);

  // حالات الأجهزة (دائمًا مع أيقونة ونص، لا يُعتمد على اللون وحده)
  static const Color statusAvailable = Color(0xFF34D399);
  static const Color statusBusy = Color(0xFF8B6CFF);
  static const Color statusReserved = Color(0xFFFBBF24);
  static const Color statusOutOfService = Color(0xFF7A829E);

  static Color forStatus(ResourceStatus status) {
    switch (status) {
      case ResourceStatus.available:
        return statusAvailable;
      case ResourceStatus.busy:
        return statusBusy;
      case ResourceStatus.reserved:
        return statusReserved;
      case ResourceStatus.outOfService:
        return statusOutOfService;
    }
  }

  static LinearGradient get brandGradient => const LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [primary, secondary],
  );
}
