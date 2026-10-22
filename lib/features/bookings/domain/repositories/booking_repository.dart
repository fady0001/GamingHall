import '../entities/booking.dart';

abstract class BookingRepository {
  /// كل الحجوزات مرتبة بوقت البداية.
  Stream<List<Booking>> watchAll();

  /// يرمي [BookingValidationException] أو [BookingConflictException].
  Future<Booking> create({
    required String customerName,
    required String phone,
    required int resourceId,
    required int playerCount,
    required DateTime startAt,
    required DateTime endAt,
    bool isOpen = false,
  });

  Future<void> cancel(int id);

  /// يحوّل الحجز إلى فاتورة جديدة تبدأ اللعب فورًا على الجهاز المحجوز.
  /// يعيد معرّف الفاتورة. يرمي [StateError] برسالة عربية عند الفشل.
  Future<int> convertToInvoice(int id);

  Future<void> markReminderShown(int id);
}
