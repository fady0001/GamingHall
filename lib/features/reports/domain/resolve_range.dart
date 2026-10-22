import 'entities/report.dart';

/// يحوّل اختيار المدير إلى فترة فعلية.
///  - today: من بداية يوم العمل الحالي [currentDayStart] حتى الآن.
///  - week: من آخر سبت (بداية الأسبوع في سوريا) حتى نهاية اليوم.
///  - month: من أول الشهر حتى نهاية اليوم.
///  - custom: كما اختار (يُمرَّر [custom] مع نهاية نصف مفتوحة).
DateRange resolveRange(
  RangePreset preset, {
  required DateTime now,
  required DateTime currentDayStart,
  DateRange? custom,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);

  switch (preset) {
    case RangePreset.today:
      return DateRange(currentDayStart, tomorrow.isAfter(now) ? tomorrow : now);
    case RangePreset.week:
      // Dart: Monday=1 ... Saturday=6, Sunday=7 → أيام منذ السبت.
      final sinceSaturday = (now.weekday - DateTime.saturday) % 7;
      return DateRange(
        DateTime(today.year, today.month, today.day - sinceSaturday),
        tomorrow,
      );
    case RangePreset.month:
      return DateRange(DateTime(now.year, now.month, 1), tomorrow);
    case RangePreset.custom:
      return custom ?? DateRange(DateTime(now.year, now.month, 1), tomorrow);
  }
}
