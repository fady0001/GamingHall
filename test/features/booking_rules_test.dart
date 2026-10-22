import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/utils/time_format.dart';
import 'package:gaming_hall/features/bookings/domain/entities/booking.dart';
import 'package:gaming_hall/features/bookings/domain/usecases/booking_rules.dart';

Booking _b(int id, int resourceId, DateTime start, DateTime end,
    {BookingStatus status = BookingStatus.scheduled, String name = 'زبون', DateTime? reminder}) {
  return Booking(
    id: id,
    customerName: name,
    phone: '',
    resourceId: resourceId,
    resourceName: 'PS $resourceId',
    playerCount: 1,
    startAt: start,
    endAt: end,
    status: status,
    createdAt: start,
    reminderShownAt: reminder,
  );
}

void main() {
  phoneAndClockTests();
  openBookingTests();
  final t = DateTime(2026, 10, 3, 18, 0);

  test('التداخل: المتلاصقان لا يتعارضان، والمتقاطعان يتعارضان', () {
    final a = t, b = t.add(const Duration(hours: 1));
    expect(bookingsOverlap(b, b.add(const Duration(hours: 1)), a, b), isFalse);
    expect(bookingsOverlap(a.subtract(const Duration(hours: 1)), a, a, b), isFalse);
    expect(bookingsOverlap(a.add(const Duration(minutes: 30)), b.add(const Duration(minutes: 30)), a, b), isTrue);
    expect(bookingsOverlap(a, b, a, b), isTrue);
    expect(bookingsOverlap(a.add(const Duration(minutes: 10)), a.add(const Duration(minutes: 20)), a, b), isTrue);
  });

  test('تذكير الحجز: داخل نافذة الساعة فقط وبدون تكرار', () {
    final booking = _b(1, 1, t, t.add(const Duration(hours: 1)));
    expect(findBookingsDueForReminder([booking], t.subtract(const Duration(minutes: 61))), isEmpty);
    expect(findBookingsDueForReminder([booking], t.subtract(const Duration(minutes: 59))), hasLength(1));
    expect(findBookingsDueForReminder([booking], t.add(const Duration(minutes: 10))), hasLength(1));
    expect(findBookingsDueForReminder([booking], t.add(const Duration(hours: 2))), isEmpty);

    final shown = _b(2, 1, t, t.add(const Duration(hours: 1)), reminder: t);
    expect(findBookingsDueForReminder([shown], t), isEmpty);

    final cancelled = _b(3, 1, t, t.add(const Duration(hours: 1)), status: BookingStatus.cancelled);
    expect(findBookingsDueForReminder([cancelled], t), isEmpty);
  });

  test('أقرب حجز للمورد ضمن النافذة', () {
    final near = _b(1, 1, t.add(const Duration(minutes: 30)), t.add(const Duration(minutes: 90)));
    final far = _b(2, 1, t.add(const Duration(hours: 5)), t.add(const Duration(hours: 6)));
    final other = _b(3, 2, t.add(const Duration(minutes: 10)), t.add(const Duration(minutes: 50)));
    expect(nearestBookingFor([far, near, other], 1, t)?.id, 1);
    expect(nearestBookingFor([far], 1, t), isNull);
    expect(nearestBookingFor([other], 1, t), isNull);
    expect(nearestBookingFor([near], 1, t.add(const Duration(hours: 3))), isNull);
  });

  test('فلترة حسب اليوم والاسم', () {
    final today = _b(1, 1, t, t.add(const Duration(hours: 1)), name: 'أحمد');
    final tomorrow = _b(2, 1, t.add(const Duration(days: 1)), t.add(const Duration(days: 1, hours: 1)), name: 'سامر');
    expect(filterBookings([tomorrow, today], day: t).map((b) => b.id), [1]);
    expect(filterBookings([tomorrow, today], query: 'احمد').map((b) => b.id), [1]);
    expect(filterBookings([tomorrow, today]).map((b) => b.id), [1, 2]);
  });
}

void phoneAndClockTests() {
  test('رقم الهاتف: إلزامي، يبدأ بـ 09، و10 أرقام', () {
    expect(validateBookingPhone(''), isNotNull);
    expect(validateBookingPhone('   '), isNotNull);
    expect(validateBookingPhone('0812345678'), isNotNull);
    expect(validateBookingPhone('091234567'), isNotNull);
    expect(validateBookingPhone('09123456789'), isNotNull);
    expect(validateBookingPhone('09abc45678'), isNotNull);
    expect(validateBookingPhone('0912345678'), isNull);
  });

  test('الوقت بنظام 12 ساعة (ص/م)', () {
    expect(formatClock(DateTime(2026, 1, 1, 20, 0)), '8:00 م');
    expect(formatClock(DateTime(2026, 1, 1, 8, 5)), '8:05 ص');
    expect(formatClock(DateTime(2026, 1, 1, 0, 0)), '12:00 ص');
    expect(formatClock(DateTime(2026, 1, 1, 12, 30)), '12:30 م');
  });
}

void openBookingTests() {
  test('الحجز المفتوح لا يمنع حجز نفس الجهاز بوقت آخر', () {
    final t = DateTime(2026, 10, 3, 20, 0);
    final open = Booking(
      id: 1, customerName: 'أ', phone: '0912345678', resourceId: 1,
      resourceName: 'PS 1', playerCount: 1, startAt: t,
      endAt: t.add(const Duration(hours: 1)), status: BookingStatus.scheduled,
      createdAt: t, isOpen: true,
    );
    expect(
      findConflictingBooking([open], 1, t.add(const Duration(minutes: 30)),
          t.add(const Duration(minutes: 90))),
      isNull,
    );
  });
}
