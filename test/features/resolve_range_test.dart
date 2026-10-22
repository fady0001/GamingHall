import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/features/reports/domain/entities/report.dart';
import 'package:gaming_hall/features/reports/domain/resolve_range.dart';

void main() {
  // السبت 3 تشرين الأول 2026 (weekday = 6)
  final now = DateTime(2026, 10, 3, 15, 30);

  test('الأسبوع يبدأ من السبت', () {
    final r = resolveRange(RangePreset.week, now: now, currentDayStart: now);
    expect(r.start, DateTime(2026, 10, 3));
    expect(r.end, DateTime(2026, 10, 4));

    final wednesday = DateTime(2026, 10, 7, 12);
    final r2 = resolveRange(RangePreset.week, now: wednesday, currentDayStart: wednesday);
    expect(r2.start, DateTime(2026, 10, 3));
  });

  test('الشهر من أوله حتى نهاية اليوم', () {
    final r = resolveRange(RangePreset.month, now: now, currentDayStart: now);
    expect(r.start, DateTime(2026, 10, 1));
    expect(r.end, DateTime(2026, 10, 4));
  });

  test('يوم العمل الحالي يبدأ من بدايته الفعلية (قد تكون أمس)', () {
    final started = DateTime(2026, 10, 2, 17, 0);
    final r = resolveRange(RangePreset.today, now: now, currentDayStart: started);
    expect(r.start, started);
    expect(r.end.isAfter(now), isTrue);
  });

  test('فترة مخصصة تُعاد كما هي', () {
    final custom = DateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 16));
    final r = resolveRange(RangePreset.custom, now: now, currentDayStart: now, custom: custom);
    expect(r.start, custom.start);
    expect(r.end, custom.end);
  });
}
