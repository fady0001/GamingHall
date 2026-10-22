import 'package:gaming_hall/features/bookings/domain/usecases/booking_rules.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../invoices/data/invoice_store.dart';
import '../domain/entities/booking.dart';
import '../domain/repositories/booking_repository.dart';
import 'reservation_guard.dart';

Booking bookingFromRow(Map<String, Object?> r) => Booking(
      id: r['id'] as int,
      customerName: r['customer_name'] as String,
      phone: (r['phone'] as String?) ?? '',
      resourceId: r['resource_id'] as int,
      resourceName: r['resource_name'] as String,
      playerCount: (r['player_count'] as int?) ?? 1,
      startAt: parseDbTime(r['start_at']),
      endAt: parseDbTime(r['end_at']),
      status: bookingStatusFromName(r['status'] as String),
      convertedInvoiceId: r['converted_invoice_id'] as int?,
      reminderShownAt: parseDbTimeOrNull(r['reminder_shown_at']),
      createdAt: parseDbTime(r['created_at']),
      isOpen: (r['is_open'] as int?) == 1,
    );

class BookingRepositoryImpl implements BookingRepository {
  final AppDatabase _db;
  BookingRepositoryImpl(this._db);

  Future<List<Booking>> _loadAll() async {
    final rows = await _db.raw.query('bookings', orderBy: 'start_at ASC');
    return rows.map(bookingFromRow).toList();
  }

  @override
  Stream<List<Booking>> watchAll() => _db.watch(_loadAll);

  @override
  Future<Booking> create({
    required String customerName,
    required String phone,
    required int resourceId,
    required int playerCount,
    required DateTime startAt,
    required DateTime endAt,
    bool isOpen = false,
  }) async {
    final name = customerName.trim();
    if (name.isEmpty) throw const BookingValidationException('اسم الزبون مطلوب');
    final phoneError = validateBookingPhone(phone);
    if (phoneError != null) throw BookingValidationException(phoneError);
    if (!endAt.isAfter(startAt)) {
      throw const BookingValidationException('وقت النهاية يجب أن يكون بعد وقت البداية');
    }
    if (startAt.isBefore(DateTime.now().subtract(const Duration(minutes: 2)))) {
      throw const BookingValidationException('لا يمكن الحجز في وقت مضى');
    }

    final id = await _db.write((txn) async {
      final resourceRows = await txn.query('resources',
          where: 'id = ? AND is_active = 1', whereArgs: [resourceId], limit: 1);
      if (resourceRows.isEmpty) {
        throw const BookingValidationException('الجهاز غير موجود');
      }
      final resource = resourceRows.first;
      if (resource['out_of_service'] == 1) {
        throw BookingValidationException(
            '"${resource['name']}" خارج الخدمة حاليًا ولا يمكن حجزه');
      }
      final maxPlayers = resource['max_players'] as int;
      if (playerCount < 1 || playerCount > maxPlayers) {
        throw BookingValidationException(
            'عدد اللاعبين يجب أن يكون بين 1 و$maxPlayers');
      }

      // تضارب مع حجز آخر أو مع لعب جارٍ على نفس الجهاز.
      await ReservationGuard.ensureCanBook(
        txn,
        resourceId: resourceId,
        resourceName: resource['name'] as String,
        startAt: startAt,
        endAt: endAt,
        isOpen: isOpen,
      );

      return txn.insert('bookings', {
        'customer_name': name,
        'phone': phone.trim(),
        'is_open': isOpen ? 1 : 0,
        'resource_id': resourceId,
        'resource_name': resource['name'],
        'player_count': playerCount,
        'start_at': dbTime(startAt),
        'end_at': dbTime(endAt),
        'status': 'scheduled',
        'created_at': dbTime(DateTime.now()),
      });
    });

    final rows =
        await _db.raw.query('bookings', where: 'id = ?', whereArgs: [id]);
    return bookingFromRow(rows.first);
  }

  @override
  Future<void> cancel(int id) async {
    await _db.write((txn) async {
      await txn.update(
        'bookings',
        {'status': 'cancelled'},
        where: "id = ? AND status = 'scheduled'",
        whereArgs: [id],
      );
    });
  }

  @override
  Future<int> convertToInvoice(int id) {
    return _db.write((txn) async {
      final rows = await txn.query('bookings',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('الحجز غير موجود');
      final booking = bookingFromRow(rows.first);
      if (booking.status != BookingStatus.scheduled) {
        throw StateError('هذا الحجز لم يعد قابلًا للتحويل');
      }

      final invoiceId =
          await InvoiceStore.createInvoice(txn, booking.customerName);
      await InvoiceStore.startPlay(
        txn,
        invoiceId: invoiceId,
        resourceId: booking.resourceId,
        playerCount: booking.playerCount,
        excludeBookingId: booking.id, // لا يتعارض الحجز مع نفسه
        guardUntil: booking.endAt, // يُفحص حتى نهاية الحجز نفسه فقط
      );
      await txn.update(
        'bookings',
        {'status': 'converted', 'converted_invoice_id': invoiceId},
        where: 'id = ?',
        whereArgs: [id],
      );
      return invoiceId;
    });
  }

  @override
  Future<void> markReminderShown(int id) async {
    await _db.write((txn) async {
      await txn.update(
        'bookings',
        {'reminder_shown_at': dbTime(DateTime.now())},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
