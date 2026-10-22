import '../../../../core/utils/time_format.dart';

/// scheduled: قادم · converted: تحوّل إلى فاتورة · cancelled: ملغى.
enum BookingStatus { scheduled, converted, cancelled }

extension BookingStatusX on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.scheduled:
        return 'قادم';
      case BookingStatus.converted:
        return 'تحوّل إلى فاتورة';
      case BookingStatus.cancelled:
        return 'ملغى';
    }
  }
}

BookingStatus bookingStatusFromName(String name) {
  for (final s in BookingStatus.values) {
    if (s.name == name) return s;
  }
  return BookingStatus.scheduled;
}

/// حجز مسبق لجهاز/طاولة بوقت محدد. اسم الجهاز يُحفظ كلقطة.
class Booking {
  final int id;
  final String customerName;
  final String phone;
  final int resourceId;
  final String resourceName;
  final int playerCount;
  final DateTime startAt;
  final DateTime endAt;
  final BookingStatus status;
  final int? convertedInvoiceId;
  final DateTime? reminderShownAt;
  final DateTime createdAt;

  /// حجز بوقت مفتوح: لا مدة محددة ولا يمنع حجز الجهاز بوقت آخر (الموظف يقرر).
  /// [endAt] هنا للعرض فقط (ساعة من البداية) ولا تُعرض كوقت نهاية.
  final bool isOpen;

  const Booking({
    required this.id,
    required this.customerName,
    required this.phone,
    required this.resourceId,
    required this.resourceName,
    required this.playerCount,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.createdAt,
    this.convertedInvoiceId,
    this.reminderShownAt,
    this.isOpen = false,
  });

  Duration get duration => endAt.difference(startAt);

  String get timeRangeLabel =>
      isOpen ? '${formatClock(startAt)} (وقت مفتوح)' : '${formatClock(startAt)} - ${formatClock(endAt)}';
}

class BookingValidationException implements Exception {
  final String message;
  const BookingValidationException(this.message);
  @override
  String toString() => message;
}

class BookingConflictException implements Exception {
  final Booking conflicting;
  const BookingConflictException(this.conflicting);

  String get message =>
      'يوجد حجز متعارض على "${conflicting.resourceName}": '
      '${conflicting.customerName} من ${formatClock(conflicting.startAt)} '
      '${conflicting.isOpen ? '(وقت مفتوح)' : 'إلى ${formatClock(conflicting.endAt)}'} (${formatDate(conflicting.startAt)})';

  @override
  String toString() => message;
}
