import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/db_utils.dart';
import '../../bookings/data/reservation_guard.dart';
import '../../days/data/work_day_store.dart';
import '../../resources/data/resource_repository_impl.dart';

/// عمليات مشتركة بين مستودعَي الفواتير والحجوزات. كلها تُستدعى داخل معاملة
/// كتابة واحدة حتى لا تبقى حالة نصف مكتملة عند أي خطأ.
class InvoiceStore {
  InvoiceStore._();

  static const int maxNameLength = 60;

  static Future<int> createInvoice(DatabaseExecutor ex, String customerName) async {
    final name = customerName.trim();
    if (name.isEmpty) throw ArgumentError('اسم الزبون مطلوب');
    if (name.length > maxNameLength) {
      throw ArgumentError('اسم الزبون طويل (الحد الأقصى $maxNameLength حرفًا)');
    }
    final day = await WorkDayStore.ensureOpenDay(ex);
    return ex.insert('invoices', {
      'customer_name': name,
      'day_id': day.id,
      'status': 'open',
      'created_at': dbTime(DateTime.now()),
    });
  }

  /// يبدأ لعبًا. يرمي [StateError] برسالة عربية إن لم يكن ممكنًا.
  static Future<int> startPlay(
    DatabaseExecutor ex, {
    required int invoiceId,
    required int resourceId,
    required int playerCount,
    int? plannedMinutes,
    int? excludeBookingId,
    DateTime? guardUntil,
  }) async {
    if (plannedMinutes != null && (plannedMinutes < 1 || plannedMinutes > 24 * 60)) {
      throw StateError('الوقت المحدد يجب أن يكون بين دقيقة و24 ساعة');
    }
    final invoiceRows = await ex.query('invoices',
        columns: ['status'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceRows.isEmpty || invoiceRows.first['status'] != 'open') {
      throw StateError('الفاتورة مغلقة أو غير موجودة');
    }

    final resourceRows = await ex.query('resources',
        where: 'id = ? AND is_active = 1', whereArgs: [resourceId], limit: 1);
    if (resourceRows.isEmpty) throw StateError('الجهاز غير موجود');
    final resource = resourceFromRow(resourceRows.first);

    if (resource.outOfService) {
      throw StateError('"${resource.name}" خارج الخدمة حاليًا');
    }
    if (playerCount < 1 || playerCount > resource.maxPlayers) {
      throw StateError(
          'عدد اللاعبين على "${resource.name}" يجب أن يكون بين 1 و${resource.maxPlayers}');
    }

    // منع التضارب مع الحجوزات (الجارية أو التي ستبدأ خلال مدة اللعب).
    await ReservationGuard.ensureCanStartPlay(
      ex,
      resourceId: resource.id,
      plannedMinutes: plannedMinutes,
      excludeBookingId: excludeBookingId,
      until: guardUntil,
    );

    try {
      return await ex.insert('play_lines', {
        'invoice_id': invoiceId,
        'resource_id': resource.id,
        'resource_name': resource.name,
        'resource_type': (resource.typeName != null && resource.typeName!.isNotEmpty)
            ? resource.typeName
            : resource.kind.name,
        'player_count': playerCount,
        'hourly_rate': resource.rateFor(playerCount).amount,
        'started_at': dbTime(DateTime.now()),
        'planned_minutes': plannedMinutes,
      });
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw StateError('"${resource.name}" مشغول حاليًا');
      }
      rethrow;
    }
  }
}
