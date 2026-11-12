import 'package:sqflite_common_ffi/sqflite_ffi.dart';


class AppSchema {
  AppSchema._();

  static const int version = 7;

  static const List<String> createStatements = [
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE manager_account (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      username TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      recovery_hash TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE resources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      type_name TEXT,
      max_players INTEGER NOT NULL,
      rate1 INTEGER NOT NULL,
      rate2 INTEGER NOT NULL,
      rate3 INTEGER NOT NULL,
      rate4 INTEGER NOT NULL,
      out_of_service INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE resource_types (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      is_enabled INTEGER NOT NULL DEFAULT 0,
      is_preset INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX idx_resource_types_name '
        'ON resource_types(name COLLATE NOCASE)',
    'CREATE UNIQUE INDEX idx_resources_name_active '
        'ON resources(name COLLATE NOCASE) WHERE is_active = 1',
    '''
    CREATE TABLE menu_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      price INTEGER NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      track_stock INTEGER NOT NULL DEFAULT 1,
      min_stock INTEGER NOT NULL DEFAULT 0,
      unit_cost INTEGER NOT NULL DEFAULT 0,
      sold_offset INTEGER,
      is_sellable INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX idx_menu_name_active '
        'ON menu_items(name COLLATE NOCASE) WHERE is_active = 1',
    '''
    CREATE TABLE work_days (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at TEXT NOT NULL,
      ended_at TEXT
    )
    ''',
    '''
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_name TEXT NOT NULL,
      day_id INTEGER NOT NULL REFERENCES work_days(id),
      status TEXT NOT NULL DEFAULT 'open',
      created_at TEXT NOT NULL,
      closed_at TEXT,
      play_total INTEGER,
      items_total INTEGER,
      minimum_adjustment INTEGER,
      rounding_delta INTEGER,
      final_total INTEGER
    )
    ''',
    'CREATE INDEX idx_invoices_day ON invoices(day_id)',
    'CREATE INDEX idx_invoices_status ON invoices(status)',
    'CREATE INDEX idx_invoices_closed_at ON invoices(closed_at)',
    '''
    CREATE TABLE play_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices(id),
      resource_id INTEGER NOT NULL REFERENCES resources(id),
      resource_name TEXT NOT NULL,
      resource_type TEXT NOT NULL,
      player_count INTEGER NOT NULL,
      hourly_rate INTEGER NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      billed_minutes INTEGER,
      charge INTEGER,
      planned_minutes INTEGER
    )
    ''',
    'CREATE INDEX idx_play_lines_invoice ON play_lines(invoice_id)',

    'CREATE UNIQUE INDEX uq_play_lines_running '
        'ON play_lines(resource_id) WHERE ended_at IS NULL',
    '''
    CREATE TABLE item_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoices(id),
      menu_item_id INTEGER NOT NULL REFERENCES menu_items(id),
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      unit_price INTEGER NOT NULL,
      quantity INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_item_lines_invoice ON item_lines(invoice_id)',
    '''
    CREATE TABLE bookings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      resource_id INTEGER NOT NULL REFERENCES resources(id),
      resource_name TEXT NOT NULL,
      player_count INTEGER NOT NULL DEFAULT 1,
      start_at TEXT NOT NULL,
      end_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'scheduled',
      converted_invoice_id INTEGER,
      reminder_shown_at TEXT,
      is_open INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX idx_bookings_start ON bookings(start_at)',
    ..._stockStatements,
    'CREATE INDEX IF NOT EXISTS idx_stock_purchases_invoice '
        'ON stock_purchases(invoice_id)',
    ..._performanceIndexes,
  ];

  /// فهارس الأداء (الإصدار 7). أهمها `item_lines(menu_item_id)`: حساب كمية
  /// المخزون يجمع مبيعات كل صنف، وبدون هذا الفهرس يمسح كل جدول item_lines
  /// لكل صنف في كل تحديث.
  static const List<String> _performanceIndexes = [
    'CREATE INDEX IF NOT EXISTS idx_item_lines_menu_item '
        'ON item_lines(menu_item_id)',
    'CREATE INDEX IF NOT EXISTS idx_stock_moves_purchase '
        'ON stock_moves(purchase_id)',
    'CREATE INDEX IF NOT EXISTS idx_stock_moves_count '
        'ON stock_moves(count_id)',
  ];

  /// جداول المخزون (الإصدار 5). تُستخدم عند الإنشاء وعند الترقية معًا، ولذلك
  /// كلها `IF NOT EXISTS`.
  ///
  /// - `stock_purchases`: مشتريات البوفيه بالطرد (عدد الطرود، قطع الطرد، سعر
  ///   الطرد، وتكلفة القطعة = سعر الطرد ÷ قطع الطرد).
  /// - `stock_moves`: دفتر حركة الكمية (موجب = دخل مخزون، سالب = تسوية جرد).
  ///   المبيعات لا تُسجَّل هنا؛ تُحسب من `item_lines`.
  /// - `stock_counts`: الجرد اليومي (صف واحد لكل صنف في اليوم).
  static const List<String> _stockStatements = [
    '''
    CREATE TABLE IF NOT EXISTS stock_purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      menu_item_id INTEGER NOT NULL,
      purchased_at TEXT NOT NULL,
      packs INTEGER NOT NULL,
      pieces_per_pack INTEGER NOT NULL,
      pack_price INTEGER NOT NULL,
      total_pieces INTEGER NOT NULL,
      unit_cost INTEGER NOT NULL,
      total_cost INTEGER NOT NULL,
      note TEXT,
      created_at TEXT NOT NULL,
      invoice_id INTEGER,
      entry_mode TEXT NOT NULL DEFAULT 'pack'
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_stock_purchases_item '
        'ON stock_purchases(menu_item_id)',
    'CREATE INDEX IF NOT EXISTS idx_stock_purchases_date '
        'ON stock_purchases(purchased_at)',
    '''
    CREATE TABLE IF NOT EXISTS stock_moves (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      menu_item_id INTEGER NOT NULL,
      kind TEXT NOT NULL,
      qty INTEGER NOT NULL,
      purchase_id INTEGER,
      count_id INTEGER,
      created_at TEXT NOT NULL,
      reason TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_stock_moves_item '
        'ON stock_moves(menu_item_id)',
    '''
    CREATE TABLE IF NOT EXISTS stock_counts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      menu_item_id INTEGER NOT NULL,
      count_date TEXT NOT NULL,
      expected INTEGER NOT NULL,
      counted INTEGER NOT NULL,
      difference INTEGER NOT NULL,
      counted_at TEXT NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_counts_item_date '
        'ON stock_counts(menu_item_id, count_date)',
    // فاتورة المشتريات: رأس الفاتورة. أسطرها في stock_purchases (invoice_id).
    '''
    CREATE TABLE IF NOT EXISTS purchase_invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchased_at TEXT NOT NULL,
      supplier TEXT,
      invoice_no TEXT,
      note TEXT,
      discount INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS purchase_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      paid_at TEXT NOT NULL,
      note TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_purchase_payments_invoice '
        'ON purchase_payments(invoice_id)',
  ];

  
  static const List<String> presetTableTypes = ['بلياردو', 'هوكي', 'بينغ بونغ'];

  static Future<void> _seedPresets(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    for (final name in presetTableTypes) {
      await db.insert(
        'resource_types',
        {
          'name': name,
          'kind': 'table',
          'is_enabled': 0,
          'is_preset': 1,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> create(Database db) async {
    for (final statement in createStatements) {
      await db.execute(statement);
    }
  }


  static Future<void> upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _upgradeTo2(db);
    if (oldVersion < 3) await _upgradeTo3(db);
    if (oldVersion < 4) await _upgradeTo4(db);
    if (oldVersion < 5) await _upgradeTo5(db);
    if (oldVersion < 6) await _upgradeTo6(db);
    if (oldVersion < 7) await _upgradeTo7(db);
  }

  static Future<void> _upgradeTo7(Database db) async {
    for (final statement in _performanceIndexes) {
      await db.execute(statement);
    }
  }

  static Future<Set<Object?>> _columns(Database db, String table) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols.map((c) => c['name']).toSet();
  }

  /// الإصدار 6: صنف "يُباع/لا يُباع"، فواتير المشتريات (عدة أصناف + دفعات)،
  /// وسبب التعديل اليدوي للمخزون. مشتريات الإصدار 5 (صنف واحد) تتحوّل كل
  /// واحدة إلى فاتورة مدفوعة بالكامل.
  static Future<void> _upgradeTo6(Database db) async {
    if (!(await _columns(db, 'menu_items')).contains('is_sellable')) {
      await db.execute(
          'ALTER TABLE menu_items ADD COLUMN is_sellable INTEGER NOT NULL DEFAULT 1');
    }
    final purchaseCols = await _columns(db, 'stock_purchases');
    if (!purchaseCols.contains('invoice_id')) {
      await db.execute('ALTER TABLE stock_purchases ADD COLUMN invoice_id INTEGER');
    }
    if (!purchaseCols.contains('entry_mode')) {
      await db.execute(
          "ALTER TABLE stock_purchases ADD COLUMN entry_mode TEXT NOT NULL DEFAULT 'pack'");
    }
    if (!(await _columns(db, 'stock_moves')).contains('reason')) {
      await db.execute('ALTER TABLE stock_moves ADD COLUMN reason TEXT');
    }
    for (final statement in _stockStatements) {
      await db.execute(statement);
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_purchases_invoice '
        'ON stock_purchases(invoice_id)');

    final old = await db.query('stock_purchases', where: 'invoice_id IS NULL');
    for (final r in old) {
      final invoiceId = await db.insert('purchase_invoices', {
        'purchased_at': r['purchased_at'],
        'note': r['note'],
        'discount': 0,
        'created_at': r['created_at'],
      });
      await db.insert('purchase_payments', {
        'invoice_id': invoiceId,
        'amount': r['total_cost'],
        'paid_at': r['purchased_at'],
      });
      await db.update('stock_purchases', {'invoice_id': invoiceId},
          where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  static Future<void> _upgradeTo5(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(menu_items)');
    final names = cols.map((c) => c['name']).toSet();
    if (!names.contains('track_stock')) {
      await db.execute(
          'ALTER TABLE menu_items ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1');
    }
    if (!names.contains('min_stock')) {
      await db.execute(
          'ALTER TABLE menu_items ADD COLUMN min_stock INTEGER NOT NULL DEFAULT 0');
    }
    if (!names.contains('unit_cost')) {
      await db.execute(
          'ALTER TABLE menu_items ADD COLUMN unit_cost INTEGER NOT NULL DEFAULT 0');
    }
    if (!names.contains('sold_offset')) {
      await db.execute('ALTER TABLE menu_items ADD COLUMN sold_offset INTEGER');
    }
    for (final statement in _stockStatements) {
      await db.execute(statement);
    }
  }

  static Future<void> _upgradeTo4(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(bookings)');
    if (cols.any((c) => c['name'] == 'is_open')) return;
    await db.execute('ALTER TABLE bookings ADD COLUMN is_open INTEGER NOT NULL DEFAULT 0');
  }

  static Future<void> _upgradeTo3(Database db) async {
    await db.delete('resource_types', where: 'is_preset = 1 AND is_enabled = 0');
    await db.update('resource_types', {'is_enabled': 1, 'is_preset': 0});
  }
  static Future<void> _upgradeTo2(Database db) async {
    await db.execute('ALTER TABLE resources ADD COLUMN type_name TEXT');
    await db.execute('ALTER TABLE play_lines ADD COLUMN planned_minutes INTEGER');
    await db.execute(
      '''
      CREATE TABLE IF NOT EXISTS resource_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 0,
        is_preset INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
      ''',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_types_name '
      'ON resource_types(name COLLATE NOCASE)',
    );
    await _seedPresets(db);


    const legacy = {
      'billiards': 'بلياردو',
      'pingPong': 'بينغ بونغ',
      'airHockey': 'هوكي',
      'foosball': 'فوتبول طاولة',
      'cards': 'طاولة ورق',
    };
    final now = DateTime.now().toIso8601String();
    for (final entry in legacy.entries) {
      final used = await db.query('resources',
          columns: ['id'], where: 'type = ?', whereArgs: [entry.key], limit: 1);
      if (used.isEmpty) continue;
      await db.insert(
        'resource_types',
        {
          'name': entry.value,
          'kind': 'table',
          'is_enabled': 1,
          'is_preset': 0,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await db.update(
        'resource_types',
        {'is_enabled': 1},
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [entry.value],
      );
      await db.update(
        'resources',
        {'type': 'table', 'type_name': entry.value},
        where: 'type = ?',
        whereArgs: [entry.key],
      );
    }
  }
}
