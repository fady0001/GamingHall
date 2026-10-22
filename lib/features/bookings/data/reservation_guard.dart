import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/db_utils.dart';
import '../../../core/utils/time_format.dart';
import '../domain/entities/booking.dart';
import '../domain/usecases/booking_rules.dart';
import 'booking_repository_impl.dart' show bookingFromRow;

/// نقطة التحقق الوحيدة من تضارب الجهاز بين **الحجوزات** و**اللعب (الفواتير)**.
/// كل مسار يحجز وقتًا على جهاز يمرّ من هنا، داخل نفس معاملة الكتابة، حتى لا
/// يتغيّر شيء بين الفحص والكتابة:
///  - حجز جديد                      → [ensureCanBook]
///  - بدء لعب (فاتورة/جهاز)          → [ensureCanStartPlay]
///  - تحويل حجز إلى فاتورة           → [ensureCanStartPlay] مع تجاهل الحجز نفسه
///  - تمديد لعب بوقت محدد            → [ensureCanStartPlay]
class ReservationGuard {
  ReservationGuard._();

  static Future<List<Booking>> _scheduledBookings(
    DatabaseExecutor ex,
    int resourceId,
  ) async {
    final rows = await ex.query('bookings',
        where: "resource_id = ? AND status = 'scheduled'",
        whereArgs: [resourceId]);
    return rows.map(bookingFromRow).toList();
  }

  /// يرمي [StateError] (رسالة عربية) إن كان لعب في الفترة [الآن، الآن + المدة)
  /// سيتداخل مع حجز قادم أو جارٍ على نفس الجهاز.
  /// [plannedMinutes] = null يعني وقتًا مفتوحًا (انظر [playWindowEnd]).
  static Future<void> ensureCanStartPlay(
    DatabaseExecutor ex, {
    required int resourceId,
    int? plannedMinutes,
    int? excludeBookingId,
    bool extending = false,
    DateTime? until,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    var end = until ?? playWindowEnd(at, plannedMinutes);
    if (!end.isAfter(at)) end = at.add(const Duration(minutes: 1));
    final conflict = findConflictingBooking(
      await _scheduledBookings(ex, resourceId),
      resourceId,
      at,
      end,
      excludeBookingId: excludeBookingId,
    );
    if (conflict != null) {
      throw StateError(playBlockedByBookingMessage(
        conflict,
        at,
        fixed: plannedMinutes != null,
        extending: extending,
      ));
    }
  }

  /// يرمي [BookingConflictException] إن تداخل مع حجز آخر، أو
  /// [BookingValidationException] إن كان الجهاز عليه لعب يتداخل مع الفترة.
  static Future<void> ensureCanBook(
    DatabaseExecutor ex, {
    required int resourceId,
    required String resourceName,
    required DateTime startAt,
    required DateTime endAt,
    bool isOpen = false,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    // الحجز المفتوح لا نهاية له: نفحص لحظة بدايته فقط (هل هي داخل حجز محدد).
    if (isOpen) endAt = startAt.add(const Duration(minutes: 1));

    final other = findConflictingBooking(
      await _scheduledBookings(ex, resourceId),
      resourceId,
      startAt,
      endAt,
    );
    if (other != null) throw BookingConflictException(other);

    // اللعب الجاري على الجهاز (أي فاتورة مفتوحة).
    final running = await ex.rawQuery(
      'SELECT pl.started_at, pl.planned_minutes, i.customer_name '
      'FROM play_lines pl JOIN invoices i ON i.id = pl.invoice_id '
      'WHERE pl.resource_id = ? AND pl.ended_at IS NULL',
      [resourceId],
    );
    for (final row in running) {
      final started = parseDbTime(row['started_at']);
      final planned = row['planned_minutes'] as int?;
      // المفتوح لا نهاية معروفة له: يشغل الجهاز حتى هذه اللحظة فقط.
      final busyUntil =
          planned != null ? started.add(Duration(minutes: planned)) : at;
      if (!bookingsOverlap(startAt, endAt, started, busyUntil)) continue;

      final who = row['customer_name'] as String;
      final detail = planned != null
          ? 'عليه لعب بوقت محدد لـ $who ينتهي الساعة ${formatClock(busyUntil)}'
          : 'عليه لعب مفتوح جارٍ حاليًا لـ $who';
      throw BookingValidationException(
          'لا يمكن الحجز: "$resourceName" $detail. '
          'اختر وقتًا لاحقًا أو جهازًا آخر.');
    }
  }
}
