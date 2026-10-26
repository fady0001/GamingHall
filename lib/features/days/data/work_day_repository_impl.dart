import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../domain/entities/work_day.dart';
import '../domain/repositories/work_day_repository.dart';
import 'work_day_store.dart';

class WorkDayRepositoryImpl implements WorkDayRepository {
  final AppDatabase _db;
  WorkDayRepositoryImpl(this._db);

  @override
  Future<WorkDay> currentDay() async {
    final open = await WorkDayStore.findOpen(_db.raw);
    if (open != null) return open;
    return _db.write((txn) => WorkDayStore.ensureOpenDay(txn));
  }

  @override
  Stream<WorkDay> watchCurrentDay() => _db.watch(currentDay);

  @override
  Future<WorkDay> startNewDay() {
    return _db.write((txn) async {
      final current = await WorkDayStore.ensureOpenDay(txn);

      final open = await txn.query(
        'invoices',
        columns: ['customer_name'],
        where: "status = 'open'",
        orderBy: 'id ASC',
      );
      if (open.isNotEmpty) {
        throw OpenInvoicesException(
          open.map((r) => r['customer_name'] as String).toList(),
        );
      }

      final now = DateTime.now();
      await txn.update(
        'work_days',
        {'ended_at': dbTime(now)},
        where: 'id = ?',
        whereArgs: [current.id],
      );
      final id = await txn.insert('work_days', {'started_at': dbTime(now)});
      return WorkDay(id: id, startedAt: now);
    });
  }

  Future<List<WorkDaySummary>> _loadSummaries(int limit) async {
    final rows = await _db.raw.rawQuery(
      '''
      SELECT d.id AS id, d.started_at AS started_at, d.ended_at AS ended_at,
             COUNT(i.id) AS invoice_count,
             COALESCE(SUM(i.final_total), 0) AS revenue
      FROM work_days d
      LEFT JOIN invoices i ON i.day_id = d.id AND i.status = 'closed'
      GROUP BY d.id
      ORDER BY d.started_at DESC, d.id DESC
      LIMIT ?
    ''',
      [limit],
    );
    return rows
        .map(
          (r) => WorkDaySummary(
            day: workDayFromRow(r),
            invoiceCount: r['invoice_count'] as int,
            totalRevenue: r['revenue'] as int,
          ),
        )
        .toList();
  }

  @override
  Stream<List<WorkDaySummary>> watchSummaries({int limit = 400}) =>
      _db.watch(() => _loadSummaries(limit));
}
