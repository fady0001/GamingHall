import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../resources/domain/entities/resource_kind.dart';
import '../domain/entities/report.dart';
import '../domain/repositories/report_repository.dart';

class ReportRepositoryImpl implements ReportRepository {
  final AppDatabase _db;
  ReportRepositoryImpl(this._db);

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Future<Report> build(DateRange range) async {
    final from = dbTime(range.start);
    final to = dbTime(range.end);
    final db = _db.raw;

    const closedInRange =
        "i.status = 'closed' AND i.closed_at >= ? AND i.closed_at < ?";

    final summaryRows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt,
             COALESCE(SUM(final_total), 0) AS revenue,
             COALESCE(SUM(play_total), 0) AS play,
             COALESCE(SUM(items_total), 0) AS items
      FROM invoices i
      WHERE $closedInRange
    ''', [from, to]);
    final s = summaryRows.first;
    final revenue = _int(s['revenue']);
    final summary = ReportSummary(
      invoiceCount: _int(s['cnt']),
      revenue: revenue,
      playRevenue: _int(s['play']),
      itemsRevenue: _int(s['items']),
    );

    final dailyRows = await db.rawQuery('''
      SELECT substr(i.closed_at, 1, 10) AS d,
             COUNT(*) AS cnt,
             COALESCE(SUM(i.final_total), 0) AS revenue
      FROM invoices i
      WHERE $closedInRange
      GROUP BY d
      ORDER BY d ASC
    ''', [from, to]);
    final daily = [
      for (final r in dailyRows)
        DailySales(r['d'] as String, _int(r['cnt']), _int(r['revenue'])),
    ];

    final resourceRows = await db.rawQuery('''
      SELECT pl.resource_id AS rid,
             COALESCE(r.name, MAX(pl.resource_name)) AS name,
             r.type AS rtype,
             r.type_name AS rtname,
             MAX(pl.resource_type) AS pltype,
             COALESCE(SUM(pl.charge), 0) AS revenue,
             COALESCE(SUM(pl.billed_minutes), 0) AS minutes,
             COUNT(*) AS sessions
      FROM play_lines pl
      JOIN invoices i ON i.id = pl.invoice_id
      LEFT JOIN resources r ON r.id = pl.resource_id
      WHERE $closedInRange
      GROUP BY pl.resource_id
    ''', [from, to]);
    final stats = [
      for (final r in resourceRows)
        ResourceStat(
          resourceId: _int(r['rid']),
          name: r['name'] as String,
          kind: kindFromTypeKey((r['rtype'] ?? r['pltype']) as String),
          typeLabel: labelForTypeKey(
              (r['rtname'] ?? r['rtype'] ?? r['pltype']) as String),
          revenue: _int(r['revenue']),
          minutes: _int(r['minutes']),
          sessions: _int(r['sessions']),
        ),
    ];
    final byRevenue = [...stats]..sort((a, b) => b.revenue.compareTo(a.revenue));
    final byMinutes = [...stats]..sort((a, b) => b.minutes.compareTo(a.minutes));

    final kindTotals = <String, int>{};
    for (final st in stats) {
      kindTotals[st.typeLabel] = (kindTotals[st.typeLabel] ?? 0) + st.revenue;
    }
    final byKind = [
      for (final e in kindTotals.entries) KindRevenue(e.key, e.value),
    ]..sort((a, b) => b.revenue.compareTo(a.revenue));

    final bookingRows = await db.rawQuery('''
      SELECT resource_name AS name, COUNT(*) AS cnt
      FROM bookings
      WHERE status != 'cancelled' AND start_at >= ? AND start_at < ?
      GROUP BY resource_id
      ORDER BY cnt DESC
      LIMIT 5
    ''', [from, to]);

    final itemRows = await db.rawQuery('''
      SELECT MAX(il.name) AS name,
             SUM(il.quantity) AS qty,
             SUM(il.quantity * il.unit_price) AS revenue
      FROM item_lines il
      JOIN invoices i ON i.id = il.invoice_id
      WHERE $closedInRange
      GROUP BY il.menu_item_id
      ORDER BY qty DESC
      LIMIT 5
    ''', [from, to]);

    final hourRows = await db.rawQuery('''
      SELECT CAST(substr(pl.started_at, 12, 2) AS INTEGER) AS hour,
             COUNT(*) AS cnt
      FROM play_lines pl
      JOIN invoices i ON i.id = pl.invoice_id
      WHERE $closedInRange
      GROUP BY hour
      ORDER BY hour ASC
    ''', [from, to]);

    return Report(
      range: range,
      summary: summary,
      daily: daily,
      topByRevenue: byRevenue.take(5).toList(),
      topByMinutes: byMinutes.take(5).toList(),
      topByBookings: [
        for (final r in bookingRows) BookingStat(r['name'] as String, _int(r['cnt'])),
      ],
      topItemsByQuantity: [
        for (final r in itemRows)
          ItemStat(r['name'] as String, _int(r['qty']), _int(r['revenue'])),
      ],
      revenueByKind: byKind,
      busiestHours: [
        for (final r in hourRows) HourStat(_int(r['hour']), _int(r['cnt'])),
      ],
    );
  }
}
