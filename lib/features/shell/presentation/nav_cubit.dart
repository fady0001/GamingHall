import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// وجهات الشريط الجانبي. `home` = الفواتير (الصفحة الرئيسية).
enum Destination {
  home,
  devices,
  bookings,
  menu,
  history,
  resources,
  reports,
  settings,
}

extension DestinationX on Destination {
  String get label {
    switch (this) {
      case Destination.home:
        return 'الفواتير';
      case Destination.devices:
        return 'الأجهزة';
      case Destination.bookings:
        return 'الحجوزات';
      case Destination.menu:
        return 'قائمة المشتريات';
      case Destination.history:
        return 'سجل الفواتير';
      case Destination.resources:
        return 'الأجهزة والأسعار';
      case Destination.reports:
        return 'التقارير';
      case Destination.settings:
        return 'الإعدادات';
    }
  }

  IconData get icon {
    switch (this) {
      case Destination.home:
        return Icons.receipt_long_rounded;
      case Destination.devices:
        return Icons.sports_esports_rounded;
      case Destination.bookings:
        return Icons.event_available_rounded;
      case Destination.menu:
        return Icons.local_cafe_rounded;
      case Destination.history:
        return Icons.history_rounded;
      case Destination.resources:
        return Icons.tune_rounded;
      case Destination.reports:
        return Icons.insights_rounded;
      case Destination.settings:
        return Icons.settings_rounded;
    }
  }

  /// صفحات لا يفتحها إلا المدير (سجل الفواتير منها). قائمة المشتريات متاحة
  /// للمدير والموظف معًا (إضافة وتعديل وحذف) ولذلك ليست ضمنها.
  bool get managerOnly {
    switch (this) {
      case Destination.history:
      case Destination.resources:
      case Destination.reports:
      case Destination.settings:
        return true;
      case Destination.home:
      case Destination.devices:
      case Destination.bookings:
      case Destination.menu:
        return false;
    }
  }

  /// يظهر تحت عنوان "الإدارة" في الشريط الجانبي.
  bool get isAdminSection =>
      this == Destination.resources ||
      this == Destination.reports ||
      this == Destination.settings;
}

class NavCubit extends Cubit<Destination> {
  NavCubit() : super(Destination.home);
  void go(Destination d) => emit(d);
}
