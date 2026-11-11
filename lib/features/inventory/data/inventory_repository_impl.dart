import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/domain/value_objects/money.dart';
import '../../menu/domain/entities/menu_category.dart';
import '../domain/entities/inventory_models.dart';
import '../domain/repositories/inventory_repository.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final AppDatabase _db;
  InventoryRepositoryImpl(this._db);

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static String? _cleanText(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// الكمية الحالية تُحسب ولا تُخزَّن:
  ///   moved = مجموع stock_moves (مشتريات + تسويات جرد + تعديل يدوي)
  ///   sold  = مجموع ما بيع من الصنف في كل الفواتير
  ///   الحالية = moved − (sold − sold_offset)
  /// حيث sold_offset = ما كان مبيعًا لحظة بدء تتبّع الصنف (فلا تُخصم المبيعات
  /// القديمة). sold_offset = NULL يعني أن التتبّع لم يبدأ بعد.
  static const String _stockSelect = '''
    SELECT m.id, m.name, m.category, m.track_stock, m.min_stock, m.unit_cost,
           m.sold_offset, m.is_sellable, m.price,
           COALESCE((SELECT SUM(qty) FROM stock_moves
                     WHERE menu_item_id = m.id), 0) AS moved,
           COALESCE((SELECT SUM(quantity) FROM item_lines
                     WHERE menu_item_id = m.id), 0) AS sold
    FROM menu_items m
  ''';

  StockRow _toStockRow(Map<String, Object?> r) {
    final offset = r['sold_offset'] as int?;
    final started = offset != null;
    final onHand =
        offset == null ? 0 : _int(r['moved']) - (_int(r['sold']) - offset);
    return StockRow(
      itemId: r['id'] as int,
      name: r['name'] as String,
      category: menuCategoryFromName(r['category'] as String),
      trackStock: dbBool(r['track_stock']),
      isSellable: dbBool(r['is_sellable']),
      price: Money(_int(r['price'])),
      minStock: _int(r['min_stock']),
      unitCost: Money(_int(r['unit_cost'])),
      started: started,
      onHand: onHand,
    );
  }

  Future<List<StockRow>> _loadStock() async {
    final rows = await _db.raw.rawQuery(
      '$_stockSelect WHERE m.is_active = 1 '
      'ORDER BY m.category ASC, m.name COLLATE NOCASE ASC',
    );
    return rows.map(_toStockRow).toList();
  }

  Future<int> _onHand(DatabaseExecutor ex, int itemId) async {
    final rows = await ex.rawQuery('$_stockSelect WHERE m.id = ?', [itemId]);
    if (rows.isEmpty) return 0;
    return _toStockRow(rows.first).onHand;
  }

  /// يبدأ تتبّع الصنف (مرة واحدة) بتثبيت ما بيع منه حتى الآن.
  Future<void> _ensureStarted(DatabaseExecutor ex, int itemId) async {
    final rows = await ex.query(
      'menu_items',
      columns: ['sold_offset'],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['sold_offset'] != null) return;
    final sold = await ex.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS s FROM item_lines '
      'WHERE menu_item_id = ?',
      [itemId],
    );
    await ex.update(
      'menu_items',
      {'sold_offset': _int(sold.first['s'])},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// تكلفة القطعة = تكلفة آخر سطر شراء متبقٍّ للصنف (0 إن لم يبقَ شيء).
  Future<void> _refreshUnitCost(DatabaseExecutor ex, int itemId) async {
    final latest = await ex.query(
      'stock_purchases',
      columns: ['unit_cost'],
      where: 'menu_item_id = ?',
      whereArgs: [itemId],
      orderBy: 'purchased_at DESC, id DESC',
      limit: 1,
    );
    await ex.update(
      'menu_items',
      {'unit_cost': latest.isEmpty ? 0 : latest.first['unit_cost']},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  @override
  Stream<List<StockRow>> watchStock() => _db.watch(_loadStock);

  // ───────────────────────── فواتير المشتريات ─────────────────────────

  Future<List<PurchaseInvoice>> _loadInvoices(int limit) async {
    final heads = await _db.raw.query(
      'purchase_invoices',
      orderBy: 'purchased_at DESC, id DESC',
      limit: limit,
    );
    if (heads.isEmpty) return const [];
    final ids = [for (final h in heads) h['id'] as int];
    final marks = List.filled(ids.length, '?').join(',');

    final lineRows = await _db.raw.rawQuery(
      '''
      SELECT p.*, m.name AS item_name
      FROM stock_purchases p
      LEFT JOIN menu_items m ON m.id = p.menu_item_id
      WHERE p.invoice_id IN ($marks)
      ORDER BY p.id ASC
      ''',
      ids,
    );
    final payRows = await _db.raw.rawQuery(
      'SELECT * FROM purchase_payments WHERE invoice_id IN ($marks) '
      'ORDER BY paid_at ASC, id ASC',
      ids,
    );

    final lines = <int, List<PurchaseLine>>{};
    for (final r in lineRows) {
      lines.putIfAbsent(r['invoice_id'] as int, () => []).add(PurchaseLine(
            id: r['id'] as int,
            itemId: r['menu_item_id'] as int,
            itemName: (r['item_name'] as String?) ?? '—',
            entryMode: (r['entry_mode'] as String?) ?? 'pack',
            packs: _int(r['packs']),
            piecesPerPack: _int(r['pieces_per_pack']),
            packPrice: Money(_int(r['pack_price'])),
            totalPieces: _int(r['total_pieces']),
            unitCost: Money(_int(r['unit_cost'])),
            totalCost: Money(_int(r['total_cost'])),
          ));
    }
    final payments = <int, List<PurchasePayment>>{};
    for (final r in payRows) {
      payments.putIfAbsent(r['invoice_id'] as int, () => []).add(PurchasePayment(
            id: r['id'] as int,
            invoiceId: r['invoice_id'] as int,
            amount: Money(_int(r['amount'])),
            paidAt: parseDbTime(r['paid_at']),
            note: r['note'] as String?,
          ));
    }

    return [
      for (final h in heads)
        PurchaseInvoice(
          id: h['id'] as int,
          purchasedAt: parseDbTime(h['purchased_at']),
          supplier: h['supplier'] as String?,
          invoiceNo: h['invoice_no'] as String?,
          note: h['note'] as String?,
          discount: Money(_int(h['discount'])),
          lines: lines[h['id'] as int] ?? const [],
          payments: payments[h['id'] as int] ?? const [],
        ),
    ];
  }

  @override
  Stream<List<PurchaseInvoice>> watchPurchaseInvoices({int limit = 200}) =>
      _db.watch(() => _loadInvoices(limit));

  @override
  Future<int> saveInvoice(PurchaseInvoiceInput input) async {
    if (input.lines.isEmpty) {
      throw ArgumentError('أضف صنفًا واحدًا على الأقل للفاتورة');
    }
    // الحساب هنا يتحقق من كل سطر (يرمي ArgumentError برسالة مفهومة).
    final calcs = [for (final l in input.lines) l.calc()];
    final itemsTotal = sumMoney(calcs.map((c) => c.totalCost));
    if (input.discount.amount < 0 || input.discount > itemsTotal) {
      throw ArgumentError('قيمة الخصم غير صالحة');
    }
    final payable = itemsTotal - input.discount;
    if (input.initialPaid.amount < 0 ||
        (input.id == null && input.initialPaid > payable)) {
      throw ArgumentError('المبلغ المدفوع أكبر من قيمة الفاتورة');
    }

    return _db.write((txn) async {
      final now = dbTime(DateTime.now());
      final at = dbTime(input.purchasedAt);
      final touched = <int>{};
      final int invoiceId;

      final header = {
        'purchased_at': at,
        'supplier': _cleanText(input.supplier),
        'invoice_no': _cleanText(input.invoiceNo),
        'note': _cleanText(input.note),
        'discount': input.discount.amount,
      };

      if (input.id == null) {
        invoiceId = await txn.insert('purchase_invoices', {
          ...header,
          'created_at': now,
        });
        if (input.initialPaid.amount > 0) {
          await txn.insert('purchase_payments', {
            'invoice_id': invoiceId,
            'amount': input.initialPaid.amount,
            'paid_at': at,
          });
        }
      } else {
        invoiceId = input.id!;
        final exists = await txn.query('purchase_invoices',
            columns: ['id'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
        if (exists.isEmpty) throw StateError('الفاتورة غير موجودة');

        final paid = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS s FROM purchase_payments '
          'WHERE invoice_id = ?',
          [invoiceId],
        );
        if (_int(paid.first['s']) > payable.amount) {
          throw StateError(
              'المدفوع حتى الآن أكبر من قيمة الفاتورة بعد التعديل. عدّل الخصم أو احذف دفعة أولًا');
        }

        // نسحب قطع الأسطر القديمة من المخزون ثم نعيد إدخال الأسطر الجديدة.
        final old = await txn.query('stock_purchases',
            columns: ['menu_item_id'],
            where: 'invoice_id = ?',
            whereArgs: [invoiceId]);
        for (final r in old) {
          touched.add(r['menu_item_id'] as int);
        }
        await txn.rawDelete(
          'DELETE FROM stock_moves WHERE purchase_id IN '
          '(SELECT id FROM stock_purchases WHERE invoice_id = ?)',
          [invoiceId],
        );
        await txn.delete('stock_purchases',
            where: 'invoice_id = ?', whereArgs: [invoiceId]);
        await txn.update('purchase_invoices', header,
            where: 'id = ?', whereArgs: [invoiceId]);
      }

      for (var i = 0; i < input.lines.length; i++) {
        final line = input.lines[i];
        final c = calcs[i];
        final item = await txn.query(
          'menu_items',
          columns: ['id'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [line.itemId],
          limit: 1,
        );
        if (item.isEmpty) throw StateError('أحد الأصناف غير موجود');

        await _ensureStarted(txn, line.itemId);
        final lineId = await txn.insert('stock_purchases', {
          'menu_item_id': line.itemId,
          'purchased_at': at,
          'packs': c.packs,
          'pieces_per_pack': c.piecesPerPack,
          'pack_price': c.packPrice.amount,
          'total_pieces': c.totalPieces,
          'unit_cost': c.unitCost.amount,
          'total_cost': c.totalCost.amount,
          'created_at': now,
          'invoice_id': invoiceId,
          'entry_mode': c.entryMode,
        });
        await txn.insert('stock_moves', {
          'menu_item_id': line.itemId,
          'kind': 'purchase',
          'qty': c.totalPieces,
          'purchase_id': lineId,
          'created_at': now,
        });
        touched.add(line.itemId);
      }

      for (final id in touched) {
        await _refreshUnitCost(txn, id);
      }
      return invoiceId;
    });
  }

  @override
  Future<void> deleteInvoice(int invoiceId) async {
    await _db.write((txn) async {
      final old = await txn.query('stock_purchases',
          columns: ['menu_item_id'],
          where: 'invoice_id = ?',
          whereArgs: [invoiceId]);
      final touched = {for (final r in old) r['menu_item_id'] as int};

      await txn.rawDelete(
        'DELETE FROM stock_moves WHERE purchase_id IN '
        '(SELECT id FROM stock_purchases WHERE invoice_id = ?)',
        [invoiceId],
      );
      await txn.delete('stock_purchases',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      await txn.delete('purchase_payments',
          where: 'invoice_id = ?', whereArgs: [invoiceId]);
      await txn.delete('purchase_invoices',
          where: 'id = ?', whereArgs: [invoiceId]);

      for (final id in touched) {
        await _refreshUnitCost(txn, id);
      }
    });
  }

  @override
  Future<void> addPayment({
    required int invoiceId,
    required Money amount,
    DateTime? paidAt,
    String? note,
  }) async {
    if (amount.amount <= 0) throw ArgumentError('أدخل مبلغ الدفعة');
    await _db.write((txn) async {
      final head = await txn.query('purchase_invoices',
          columns: ['discount'],
          where: 'id = ?',
          whereArgs: [invoiceId],
          limit: 1);
      if (head.isEmpty) throw StateError('الفاتورة غير موجودة');

      final totals = await txn.rawQuery(
        '''
        SELECT
          COALESCE((SELECT SUM(total_cost) FROM stock_purchases
                    WHERE invoice_id = ?), 0) AS items,
          COALESCE((SELECT SUM(amount) FROM purchase_payments
                    WHERE invoice_id = ?), 0) AS paid
        ''',
        [invoiceId, invoiceId],
      );
      final remaining = _int(totals.first['items']) -
          _int(head.first['discount']) -
          _int(totals.first['paid']);
      if (amount.amount > remaining) {
        throw StateError('المبلغ أكبر من المتبقي على الفاتورة');
      }
      await txn.insert('purchase_payments', {
        'invoice_id': invoiceId,
        'amount': amount.amount,
        'paid_at': dbTime(paidAt ?? DateTime.now()),
        'note': _cleanText(note),
      });
    });
  }

  @override
  Future<void> deletePayment(int paymentId) async {
    await _db.write((txn) =>
        txn.delete('purchase_payments', where: 'id = ?', whereArgs: [paymentId]));
  }

  // ───────────────────────── التعديل اليدوي ─────────────────────────

  @override
  Future<void> adjustStock({
    required int itemId,
    required StockAdjustMode mode,
    required int quantity,
    required String reason,
  }) async {
    final why = reason.trim();
    if (why.isEmpty) throw ArgumentError('اكتب سبب التعديل');
    if (quantity < 0 || quantity > 1000000) {
      throw ArgumentError('الكمية غير صالحة');
    }
    if (mode != StockAdjustMode.setTo && quantity == 0) {
      throw ArgumentError('أدخل عددًا أكبر من صفر');
    }

    await _db.write((txn) async {
      final item = await txn.query('menu_items',
          columns: ['id'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [itemId],
          limit: 1);
      if (item.isEmpty) throw StateError('الصنف غير موجود');

      await _ensureStarted(txn, itemId);
      final current = await _onHand(txn, itemId);
      final int delta;
      switch (mode) {
        case StockAdjustMode.increase:
          delta = quantity;
        case StockAdjustMode.decrease:
          delta = -quantity;
        case StockAdjustMode.setTo:
          delta = quantity - current;
      }
      if (delta == 0) throw StateError('الكمية لم تتغيّر');

      await txn.insert('stock_moves', {
        'menu_item_id': itemId,
        'kind': 'manual',
        'qty': delta,
        'reason': why,
        'created_at': dbTime(DateTime.now()),
      });
    });
  }

  Future<List<StockAdjustment>> _loadAdjustments(int limit) async {
    final rows = await _db.raw.rawQuery(
      '''
      SELECT s.id, s.menu_item_id, s.qty, s.reason, s.created_at,
             m.name AS item_name
      FROM stock_moves s
      LEFT JOIN menu_items m ON m.id = s.menu_item_id
      WHERE s.kind = 'manual'
      ORDER BY s.id DESC
      LIMIT ?
      ''',
      [limit],
    );
    return [
      for (final r in rows)
        StockAdjustment(
          id: r['id'] as int,
          itemId: r['menu_item_id'] as int,
          itemName: (r['item_name'] as String?) ?? '—',
          qty: _int(r['qty']),
          reason: (r['reason'] as String?) ?? '',
          createdAt: parseDbTime(r['created_at']),
        ),
    ];
  }

  @override
  Stream<List<StockAdjustment>> watchAdjustments({int limit = 300}) =>
      _db.watch(() => _loadAdjustments(limit));

  // ───────────────────────── الأصناف والإعدادات ─────────────────────────

  @override
  Future<int> createStockItem({
    required String name,
    required MenuCategory category,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('اسم الصنف مطلوب');
    try {
      return await _db.write((txn) => txn.insert('menu_items', {
            'name': clean,
            'category': category.name,
            'price': 0,
            'is_active': 1,
            'is_sellable': 0,
            'created_at': dbTime(DateTime.now()),
          }));
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw StateError('يوجد صنف بنفس الاسم "$clean"');
      }
      rethrow;
    }
  }

  @override
  Future<void> updateStockSettings({
    required int itemId,
    required bool trackStock,
    required int minStock,
    required bool isSellable,
    Money? price,
  }) async {
    if (minStock < 0) throw ArgumentError('حد التنبيه لا يمكن أن يكون سالبًا');
    if (isSellable && (price == null || price.amount <= 0)) {
      throw ArgumentError('أدخل سعر البيع');
    }
    await _db.write((txn) => txn.update(
          'menu_items',
          {
            'track_stock': boolToDb(trackStock),
            'min_stock': minStock,
            'is_sellable': boolToDb(isSellable),
            if (isSellable) 'price': price!.amount,
          },
          where: 'id = ?',
          whereArgs: [itemId],
        ));
  }

  // ───────────────────────── الجرد ─────────────────────────

  Future<List<CountRecord>> _loadCounts(String date) async {
    final rows = await _db.raw.rawQuery(
      '''
      SELECT c.*, m.name AS item_name
      FROM stock_counts c
      LEFT JOIN menu_items m ON m.id = c.menu_item_id
      WHERE c.count_date = ?
      ORDER BY m.name COLLATE NOCASE ASC
      ''',
      [date],
    );
    return [
      for (final r in rows)
        CountRecord(
          id: r['id'] as int,
          itemId: r['menu_item_id'] as int,
          itemName: (r['item_name'] as String?) ?? '—',
          date: r['count_date'] as String,
          expected: _int(r['expected']),
          counted: _int(r['counted']),
          countedAt: parseDbTime(r['counted_at']),
        ),
    ];
  }

  @override
  Stream<List<CountRecord>> watchCounts(String date) =>
      _db.watch(() => _loadCounts(date));

  @override
  Future<int> saveCounts(String date, List<CountEntry> entries) async {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw ArgumentError('تاريخ الجرد غير صالح');
    }
    for (final e in entries) {
      if (e.counted < 0 || e.counted > 1000000) {
        throw ArgumentError('كمية الجرد غير صالحة');
      }
    }
    if (entries.isEmpty) return 0;

    return _db.write((txn) async {
      var saved = 0;
      final now = dbTime(DateTime.now());
      for (final e in entries) {
        final item = await txn.query(
          'menu_items',
          columns: ['id'],
          where: 'id = ? AND is_active = 1',
          whereArgs: [e.itemId],
          limit: 1,
        );
        if (item.isEmpty) continue;

        await _ensureStarted(txn, e.itemId);

        // إعادة الجرد في نفس اليوم: نلغي تسويته السابقة أولًا حتى يُحسب
        // "المتوقع" من حركات المخزون الحقيقية لا من تسوية قديمة.
        final existing = await txn.query(
          'stock_counts',
          columns: ['id'],
          where: 'menu_item_id = ? AND count_date = ?',
          whereArgs: [e.itemId, date],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          await txn.delete('stock_moves',
              where: 'count_id = ?', whereArgs: [existing.first['id']]);
        }

        final expected = await _onHand(txn, e.itemId);
        final diff = e.counted - expected;

        final int countId;
        if (existing.isNotEmpty) {
          countId = existing.first['id'] as int;
          await txn.update(
            'stock_counts',
            {
              'expected': expected,
              'counted': e.counted,
              'difference': diff,
              'counted_at': now,
            },
            where: 'id = ?',
            whereArgs: [countId],
          );
        } else {
          countId = await txn.insert('stock_counts', {
            'menu_item_id': e.itemId,
            'count_date': date,
            'expected': expected,
            'counted': e.counted,
            'difference': diff,
            'counted_at': now,
          });
        }

        if (diff != 0) {
          await txn.insert('stock_moves', {
            'menu_item_id': e.itemId,
            'kind': 'count',
            'qty': diff,
            'count_id': countId,
            'created_at': now,
          });
        }
        saved++;
      }
      return saved;
    });
  }
}
