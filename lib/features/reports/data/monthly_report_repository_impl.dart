import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/utils/time_format.dart';
import '../../expenses/domain/entities/expense.dart';
import '../domain/entities/monthly_report.dart';
import '../domain/entities/report.dart' show ItemStat;
import '../domain/repositories/monthly_report_repository.dart';

class MonthlyReportRepositoryImpl implements MonthlyReportRepository {
  final AppDatabase _db;
  MonthlyReportRepositoryImpl(this._db);

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Future<MonthlyReport> build(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final from = dbTime(start);
    final to = dbTime(end);
    final fromDay = formatDate(start);
    final toDay = formatDate(end);
    final db = _db.raw;

    // ── الإيراد: الفواتير المغلقة حسب يوم العمل ──
    const closedInMonth = "i.status = 'closed' "
        'AND d.started_at >= ? AND d.started_at < ?';

    final rev = (await db.rawQuery('''
      SELECT COUNT(*) AS cnt,
             COALESCE(SUM(i.play_total), 0) AS play,
             COALESCE(SUM(i.items_total), 0) AS bar,
             COALESCE(SUM(i.final_total), 0) AS total
      FROM invoices i
      JOIN work_days d ON d.id = i.day_id
      WHERE $closedInMonth
    ''', [from, to])).first;
    final play = _int(rev['play']);
    final bar = _int(rev['bar']);
    final total = _int(rev['total']);

    final itemRows = await db.rawQuery('''
      SELECT MAX(il.name) AS name,
             SUM(il.quantity) AS qty,
             SUM(il.quantity * il.unit_price) AS revenue
      FROM item_lines il
      JOIN invoices i ON i.id = il.invoice_id
      JOIN work_days d ON d.id = i.day_id
      WHERE $closedInMonth
      GROUP BY il.menu_item_id
      ORDER BY qty DESC, revenue DESC
      LIMIT 10
    ''', [from, to]);

    // ── مشتريات البوفيه: الدفعات المسدّدة داخل الشهر ──
    final paid = (await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS s
      FROM purchase_payments
      WHERE paid_at >= ? AND paid_at < ?
    ''', [from, to])).first;

    // ديون المشتريات حتى نهاية الشهر: (مجموع الأسطر − الخصم) − ما دُفع حتى ذلك.
    final unpaid = (await db.rawQuery('''
      SELECT COALESCE(SUM(MAX(0, payable - paid)), 0) AS s
      FROM (
        SELECT
          COALESCE((SELECT SUM(p.total_cost) FROM stock_purchases p
                    WHERE p.invoice_id = h.id), 0) - h.discount AS payable,
          COALESCE((SELECT SUM(x.amount) FROM purchase_payments x
                    WHERE x.invoice_id = h.id AND x.paid_at < ?), 0) AS paid
        FROM purchase_invoices h
        WHERE h.purchased_at < ?
      )
    ''', [to, to])).first;

    // ── المصاريف حسب النوع ──
    final expenseRows = await db.rawQuery('''
      SELECT kind, COALESCE(SUM(amount), 0) AS s
      FROM expenses
      WHERE is_deleted = 0 AND expense_date >= ? AND expense_date < ?
      GROUP BY kind
    ''', [from, to]);
    final expenses = <ExpenseKind, int>{};
    for (final r in expenseRows) {
      final k = expenseKindFromName(r['kind'] as String);
      expenses[k] = (expenses[k] ?? 0) + _int(r['s']);
    }

    final withdrawerRows = await db.rawQuery('''
      SELECT withdrawer, COUNT(*) AS cnt, COALESCE(SUM(amount), 0) AS s
      FROM expenses
      WHERE is_deleted = 0 AND kind = 'withdrawals'
        AND expense_date >= ? AND expense_date < ?
      GROUP BY withdrawer
      ORDER BY s DESC
    ''', [from, to]);

    final reserve = (await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS s
      FROM expenses
      WHERE is_deleted = 0 AND kind = 'reserve' AND expense_date < ?
    ''', [to])).first;

    // ── فروقات الجرد ──
    final diffRows = await db.rawQuery('''
      SELECT COALESCE(m.name, '—') AS name,
             COALESCE(m.unit_cost, 0) AS unit_cost,
             SUM(c.difference) AS diff
      FROM stock_counts c
      LEFT JOIN menu_items m ON m.id = c.menu_item_id
      WHERE c.count_date >= ? AND c.count_date < ?
      GROUP BY c.menu_item_id
      HAVING SUM(c.difference) != 0
    ''', [fromDay, toDay]);
    final diffs = [
      for (final r in diffRows)
        StockDifference(
            r['name'] as String, _int(r['diff']), _int(r['unit_cost'])),
    ]..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return MonthlyReport(
      year: year,
      month: month,
      invoiceCount: _int(rev['cnt']),
      playRevenue: play,
      barRevenue: bar,
      adjustments: total - play - bar,
      totalRevenue: total,
      buffetPurchases: _int(paid['s']),
      expenses: expenses,
      withdrawers: [
        for (final r in withdrawerRows)
          WithdrawerTotal(
            ((r['withdrawer'] as String?) ?? '').trim().isEmpty
                ? 'بدون اسم'
                : (r['withdrawer'] as String).trim(),
            _int(r['cnt']),
            _int(r['s']),
          ),
      ],
      unpaidPurchases: _int(unpaid['s']),
      reserveBalance: _int(reserve['s']),
      topItems: [
        for (final r in itemRows)
          ItemStat(r['name'] as String, _int(r['qty']), _int(r['revenue'])),
      ],
      stockDifferences: diffs,
    );
  }

  @override
  Future<DateTime?> earliestMonth() async {
    final rows = await _db.raw.rawQuery('''
      SELECT MIN(t) AS t FROM (
        SELECT MIN(started_at) AS t FROM work_days
        UNION ALL
        SELECT MIN(expense_date) AS t FROM expenses WHERE is_deleted = 0
      )
    ''');
    final value = rows.first['t'] as String?;
    if (value == null) return null;
    final t = DateTime.parse(value);
    return DateTime(t.year, t.month, 1);
  }
}
