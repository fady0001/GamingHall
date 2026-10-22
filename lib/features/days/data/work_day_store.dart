import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/db_utils.dart';
import '../domain/entities/work_day.dart';

WorkDay workDayFromRow(Map<String, Object?> r) => WorkDay(
      id: r['id'] as int,
      startedAt: parseDbTime(r['started_at']),
      endedAt: parseDbTimeOrNull(r['ended_at']),
    );

/// منطق مشترك لضمان وجود يوم عمل مفتوح (يُستدعى داخل معاملة كتابة).
class WorkDayStore {
  WorkDayStore._();

  static Future<WorkDay?> findOpen(DatabaseExecutor ex) async {
    final rows = await ex.query(
      'work_days',
      where: 'ended_at IS NULL',
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : workDayFromRow(rows.first);
  }

  static Future<WorkDay> ensureOpenDay(DatabaseExecutor ex) async {
    final open = await findOpen(ex);
    if (open != null) return open;
    final now = DateTime.now();
    final id = await ex.insert('work_days', {'started_at': dbTime(now)});
    return WorkDay(id: id, startedAt: now);
  }
}
