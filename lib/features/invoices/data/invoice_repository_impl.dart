import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/domain/usecases/billing.dart';
import '../../../core/domain/value_objects/money.dart';
import '../../../core/utils/arabic_search.dart';
import '../../../core/utils/time_format.dart';
import '../../bookings/data/reservation_guard.dart';
import '../../menu/domain/entities/menu_category.dart';
import '../../resources/domain/entities/resource_kind.dart';
import '../../settings/data/settings_store.dart';
import '../domain/entities/invoice.dart';
import '../domain/repositories/invoice_repository.dart';
import 'invoice_store.dart';

class InvoiceRepositoryImpl implements InvoiceRepository {
  final AppDatabase _db;
  InvoiceRepositoryImpl(this._db);

  // ---------------------------------------------------------------- القراءة

  PlayLine _playLineFromRow(Map<String, Object?> r) => PlayLine(
    id: r['id'] as int,
    invoiceId: r['invoice_id'] as int,
    resourceId: r['resource_id'] as int,
    resourceName: r['resource_name'] as String,
    resourceKind: kindFromTypeKey(r['resource_type'] as String),
    typeKey: r['resource_type'] as String,
    playerCount: r['player_count'] as int,
    hourlyRate: Money(r['hourly_rate'] as int),
    startedAt: parseDbTime(r['started_at']),
    endedAt: parseDbTimeOrNull(r['ended_at']),
    billedMinutes: r['billed_minutes'] as int?,
    charge: r['charge'] == null ? null : Money(r['charge'] as int),
    plannedMinutes: r['planned_minutes'] as int?,
  );

  ItemLine _itemLineFromRow(Map<String, Object?> r) => ItemLine(
    id: r['id'] as int,
    invoiceId: r['invoice_id'] as int,
    menuItemId: r['menu_item_id'] as int,
    name: r['name'] as String,
    category: menuCategoryFromName(r['category'] as String),
    unitPrice: Money(r['unit_price'] as int),
    quantity: r['quantity'] as int,
  );

  Future<List<Invoice>> _assemble(
    DatabaseExecutor ex,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final marks = List.filled(ids.length, '?').join(',');

    final lineRows = await ex.rawQuery(
      'SELECT * FROM play_lines WHERE invoice_id IN ($marks) ORDER BY id ASC',
      ids,
    );
    final itemRows = await ex.rawQuery(
      'SELECT * FROM item_lines WHERE invoice_id IN ($marks) ORDER BY id ASC',
      ids,
    );

    final lines = <int, List<PlayLine>>{};
    for (final r in lineRows) {
      lines
          .putIfAbsent(r['invoice_id'] as int, () => [])
          .add(_playLineFromRow(r));
    }
    final items = <int, List<ItemLine>>{};
    for (final r in itemRows) {
      items
          .putIfAbsent(r['invoice_id'] as int, () => [])
          .add(_itemLineFromRow(r));
    }

    return [
      for (final r in rows)
        () {
          final id = r['id'] as int;
          final closed = r['status'] == 'closed';
          InvoiceTotals? totals;
          if (closed) {
            final play = Money((r['play_total'] as int?) ?? 0);
            final itemsTotal = Money((r['items_total'] as int?) ?? 0);
            totals = InvoiceTotals(
              playTotal: play,
              itemsTotal: itemsTotal,
              subtotal: play + itemsTotal,
              minimumAdjustment: Money((r['minimum_adjustment'] as int?) ?? 0),
              roundingDelta: (r['rounding_delta'] as int?) ?? 0,
              finalTotal: Money((r['final_total'] as int?) ?? 0),
            );
          }
          return Invoice(
            id: id,
            customerName: r['customer_name'] as String,
            dayId: r['day_id'] as int,
            status: closed ? InvoiceStatus.closed : InvoiceStatus.open,
            createdAt: parseDbTime(r['created_at']),
            closedAt: parseDbTimeOrNull(r['closed_at']),
            playLines: lines[id] ?? const [],
            itemLines: items[id] ?? const [],
            settledTotals: totals,
          );
        }(),
    ];
  }

  Future<List<Invoice>> _loadOpen() async {
    final rows = await _db.raw.query(
      'invoices',
      where: "status = 'open'",
      orderBy: 'id DESC',
    );
    return _assemble(_db.raw, rows);
  }

  Future<List<Invoice>> _loadByDay(int dayId) async {
    final rows = await _db.raw.query(
      'invoices',
      where: 'day_id = ?',
      whereArgs: [dayId],
      orderBy: 'id DESC',
    );
    return _assemble(_db.raw, rows);
  }

  @override
  Stream<List<Invoice>> watchOpen() => _db.watch(_loadOpen);

  @override
  Stream<List<Invoice>> watchByDay(int dayId) =>
      _db.watch(() => _loadByDay(dayId));

  @override
  Future<Invoice?> getById(int id) async {
    final rows = await _db.raw.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final list = await _assemble(_db.raw, rows);
    return list.isEmpty ? null : list.first;
  }

  @override
  Stream<Invoice?> watchById(int id) => _db.watch(() => getById(id));

  @override
  Future<List<Invoice>> search(
    InvoiceSearchFilter filter, {
    int limit = 300,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (filter.closedOnly) where.add("status = 'closed'");
    if (filter.dayId != null) {
      where.add('day_id = ?');
      args.add(filter.dayId);
    }
    if (filter.date != null) {
      where.add('substr(created_at, 1, 10) = ?');
      args.add(formatDate(filter.date!));
    }

    final rows = await _db.raw.query(
      'invoices',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'id DESC',
      limit: 2000,
    );
    var invoices = await _assemble(_db.raw, rows);

    final raw = filter.query.trim();
    if (raw.isNotEmpty) {
      final idText = raw.startsWith('#') ? raw.substring(1) : raw;
      final idQuery = int.tryParse(idText);
      final q = normalizeForSearch(idText);
      invoices = invoices
          .where(
            (i) =>
                (idQuery != null && i.id == idQuery) ||
                normalizeForSearch(i.customerName).contains(q),
          )
          .toList();
    }
    return invoices.take(limit).toList();
  }

  // ---------------------------------------------------------------- الكتابة

  @override
  Future<Invoice> create(String customerName) async {
    final id = await _db.write(
      (txn) => InvoiceStore.createInvoice(txn, customerName),
    );
    return (await getById(id))!;
  }

  @override
  Future<void> startPlay({
    required int invoiceId,
    required int resourceId,
    required int playerCount,
    int? plannedMinutes,
  }) async {
    await _db.write(
      (txn) => InvoiceStore.startPlay(
        txn,
        invoiceId: invoiceId,
        resourceId: resourceId,
        playerCount: playerCount,
        plannedMinutes: plannedMinutes,
      ),
    );
  }

  /// يوقف خط لعب داخل معاملة قائمة ويعيد أجره.
  Future<void> _stopLine(
    DatabaseExecutor ex,
    Map<String, Object?> lineRow,
    DateTime now,
  ) async {
    final started = parseDbTime(lineRow['started_at']);
    // الوقت المحدد لا يُحاسَب بعد نهايته مهما تأخّر الإيقاف.
    final plannedMinutes = lineRow['planned_minutes'] as int?;
    if (plannedMinutes != null) {
      final plannedEnd = started.add(Duration(minutes: plannedMinutes));
      if (now.isAfter(plannedEnd)) now = plannedEnd;
    }
    final elapsed = now.difference(started);
    final minutes = billedMinutesFor(
      elapsed.isNegative ? Duration.zero : elapsed,
    );
    final charge = chargeForMinutes(
      hourlyRate: Money(lineRow['hourly_rate'] as int),
      minutes: minutes,
    );
    await ex.update(
      'play_lines',
      {
        'ended_at': dbTime(now),
        'billed_minutes': minutes,
        'charge': charge.amount,
      },
      where: 'id = ?',
      whereArgs: [lineRow['id']],
    );
  }

  @override
  Future<void> stopPlay(int playLineId) async {
    await _db.write((txn) async {
      final rows = await txn.query(
        'play_lines',
        where: 'id = ?',
        whereArgs: [playLineId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('خط اللعب غير موجود');
      if (rows.first['ended_at'] != null) {
        throw StateError('تم إيقاف هذا اللعب مسبقًا');
      }
      await _stopLine(txn, rows.first, DateTime.now());
    });
  }

  @override
  Future<List<PlayLine>> endExpiredFixedLines() async {
    final endedIds = await _db.write((txn) async {
      final now = DateTime.now();
      final rows = await txn.rawQuery(
        'SELECT * FROM play_lines WHERE ended_at IS NULL AND planned_minutes IS NOT NULL',
      );
      final ids = <int>[];
      for (final row in rows) {
        final started = parseDbTime(row['started_at']);
        final end = started.add(
          Duration(minutes: row['planned_minutes'] as int),
        );
        if (!now.isBefore(end)) {
          await _stopLine(
            txn,
            row,
            now,
          ); // يُقصّ تلقائيًا عند نهاية الوقت المحدد
          ids.add(row['id'] as int);
        }
      }
      return ids;
    });
    if (endedIds.isEmpty) return const [];
    final marks = List.filled(endedIds.length, '?').join(',');
    final rows = await _db.raw.rawQuery(
      'SELECT * FROM play_lines WHERE id IN ($marks)',
      endedIds,
    );
    return rows.map(_playLineFromRow).toList();
  }

  @override
  Future<void> extendPlay({
    required int playLineId,
    required int extraMinutes,
  }) async {
    if (extraMinutes < 1 || extraMinutes > 24 * 60) {
      throw ArgumentError('مدة التمديد يجب أن تكون بين دقيقة و24 ساعة');
    }
    await _db.write((txn) async {
      final rows = await txn.query(
        'play_lines',
        where: 'id = ?',
        whereArgs: [playLineId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('خط اللعب غير موجود');
      final line = rows.first;
      final planned = line['planned_minutes'] as int?;
      if (planned == null) {
        throw StateError('التمديد للوقت المحدد فقط. الوقت المفتوح لا ينتهي.');
      }
      await _requireOpenInvoice(txn, line['invoice_id'] as int);

      if (line['ended_at'] == null) {
        // ما زال جاريًا (لم ينتهِ بعد): نزيد وقته الأصلي.
        final total = planned + extraMinutes;
        if (total > 24 * 60) throw StateError('الوقت الإجمالي كبير جدًا');
        // الفترة الكاملة من الآن حتى النهاية الجديدة يجب ألا تلامس حجزًا.
        final newEnd = parseDbTime(
          line['started_at'],
        ).add(Duration(minutes: total));
        await ReservationGuard.ensureCanStartPlay(
          txn,
          resourceId: line['resource_id'] as int,
          plannedMinutes: total,
          until: newEnd,
          extending: true,
        );
        await txn.update(
          'play_lines',
          {'planned_minutes': total},
          where: 'id = ?',
          whereArgs: [playLineId],
        );
        return;
      }

      // انتهى: خط جديد من الآن (بنفس الجهاز والسعر) حتى لا يُحاسَب وقت الانتظار.
      final resourceRows = await txn.query(
        'resources',
        where: 'id = ? AND is_active = 1',
        whereArgs: [line['resource_id']],
        limit: 1,
      );
      if (resourceRows.isEmpty) throw StateError('الجهاز لم يعد موجودًا');
      if (dbBool(resourceRows.first['out_of_service'])) {
        throw StateError('الجهاز خارج الخدمة حاليًا');
      }
      await ReservationGuard.ensureCanStartPlay(
        txn,
        resourceId: line['resource_id'] as int,
        plannedMinutes: extraMinutes,
        extending: true,
      );
      try {
        await txn.insert('play_lines', {
          'invoice_id': line['invoice_id'],
          'resource_id': line['resource_id'],
          'resource_name': line['resource_name'],
          'resource_type': line['resource_type'],
          'player_count': line['player_count'],
          'hourly_rate': line['hourly_rate'],
          'started_at': dbTime(DateTime.now()),
          'planned_minutes': extraMinutes,
        });
      } catch (e) {
        if (isUniqueViolation(e)) {
          throw StateError('الجهاز مشغول الآن بلعب آخر، لا يمكن تمديده.');
        }
        rethrow;
      }
    });
  }

  Future<void> _requireOpenInvoice(DatabaseExecutor ex, int invoiceId) async {
    final rows = await ex.query(
      'invoices',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['status'] != 'open') {
      throw StateError('الفاتورة مغلقة أو غير موجودة');
    }
  }

  @override
  Future<void> addItem({
    required int invoiceId,
    required int menuItemId,
    required int quantity,
  }) async {
    if (quantity <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
    await _db.write((txn) async {
      await _requireOpenInvoice(txn, invoiceId);

      final menuRows = await txn.query(
        'menu_items',
        where: 'id = ? AND is_active = 1',
        whereArgs: [menuItemId],
        limit: 1,
      );
      if (menuRows.isEmpty) {
        throw StateError('الصنف غير موجود في قائمة المشتريات');
      }
      final menu = menuRows.first;

      final existing = await txn.query(
        'item_lines',
        where: 'invoice_id = ? AND menu_item_id = ? AND unit_price = ?',
        whereArgs: [invoiceId, menuItemId, menu['price']],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final newQty = (existing.first['quantity'] as int) + quantity;
        if (newQty > 999) throw StateError('الكمية كبيرة جدًا');
        await txn.update(
          'item_lines',
          {'quantity': newQty},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await txn.insert('item_lines', {
          'invoice_id': invoiceId,
          'menu_item_id': menuItemId,
          'name': menu['name'],
          'category': menu['category'],
          'unit_price': menu['price'],
          'quantity': quantity,
        });
      }
    });
  }

  @override
  Future<void> setItemQuantity(int itemLineId, int quantity) async {
    await _db.write((txn) async {
      final rows = await txn.query(
        'item_lines',
        where: 'id = ?',
        whereArgs: [itemLineId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await _requireOpenInvoice(txn, rows.first['invoice_id'] as int);
      if (quantity <= 0) {
        await txn.delete(
          'item_lines',
          where: 'id = ?',
          whereArgs: [itemLineId],
        );
      } else {
        if (quantity > 999) throw StateError('الكمية كبيرة جدًا');
        await txn.update(
          'item_lines',
          {'quantity': quantity},
          where: 'id = ?',
          whereArgs: [itemLineId],
        );
      }
    });
  }

  @override
  Future<Invoice> checkout(int invoiceId) async {
    await _db.write((txn) async {
      await _requireOpenInvoice(txn, invoiceId);
      final now = DateTime.now();

      // 1) إيقاف كل لعب جارٍ بنفس اللحظة.
      final running = await txn.query(
        'play_lines',
        where: 'invoice_id = ? AND ended_at IS NULL',
        whereArgs: [invoiceId],
      );
      for (final line in running) {
        await _stopLine(txn, line, now);
      }

      // 2) المجاميع.
      final lines = await txn.query(
        'play_lines',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      final items = await txn.query(
        'item_lines',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      if (lines.isEmpty && items.isEmpty) {
        throw StateError('الفاتورة فارغة. أضف لعبًا أو أصنافًا قبل المحاسبة.');
      }

      final policy = await SettingsStore.readBillingPolicy(txn);
      final totals = computeInvoiceTotals(
        playCharges: [for (final l in lines) Money(l['charge'] as int)],
        itemTotals: [
          for (final i in items)
            Money((i['unit_price'] as int) * (i['quantity'] as int)),
        ],
        policy: policy,
      );

      // 3) إغلاق الفاتورة بتثبيت المجاميع.
      await txn.update(
        'invoices',
        {
          'status': 'closed',
          'closed_at': dbTime(now),
          'play_total': totals.playTotal.amount,
          'items_total': totals.itemsTotal.amount,
          'minimum_adjustment': totals.minimumAdjustment.amount,
          'rounding_delta': totals.roundingDelta,
          'final_total': totals.finalTotal.amount,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
    return (await getById(invoiceId))!;
  }

  @override
  Future<void> deleteIfEmpty(int invoiceId) async {
    await _db.write((txn) async {
      await _requireOpenInvoice(txn, invoiceId);
      final lines = await txn.rawQuery(
        'SELECT 1 FROM play_lines WHERE invoice_id = ? LIMIT 1',
        [invoiceId],
      );
      final items = await txn.rawQuery(
        'SELECT 1 FROM item_lines WHERE invoice_id = ? LIMIT 1',
        [invoiceId],
      );
      if (lines.isNotEmpty || items.isNotEmpty) {
        throw StateError('لا يمكن حذف فاتورة فيها لعب أو طلبات.');
      }
      await txn.delete('invoices', where: 'id = ?', whereArgs: [invoiceId]);
    });
  }
}
