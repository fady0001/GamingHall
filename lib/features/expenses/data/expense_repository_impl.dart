import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/domain/validation_exception.dart';
import '../../../core/domain/value_objects/money.dart';
import '../../../core/utils/time_format.dart';
import '../domain/entities/expense.dart';
import '../domain/repositories/expense_repository.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  final AppDatabase _db;
  ExpenseRepositoryImpl(this._db);

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  Expense _toExpense(Map<String, Object?> r) => Expense(
        id: r['id'] as int,
        kind: expenseKindFromName(r['kind'] as String),
        amount: Money(_int(r['amount'])),
        description: (r['description'] as String?) ?? '',
        date: parseDbTime(r['expense_date']),
        withdrawer: r['withdrawer'] as String?,
        createdAt: parseDbTime(r['created_at']),
        updatedAt: parseDbTime(r['updated_at']),
      );

  static Map<String, Object?>? _decode(Object? json) {
    if (json == null) return null;
    try {
      final value = jsonDecode(json as String);
      return value is Map<String, Object?> ? value : null;
    } catch (_) {
      return null;
    }
  }

  ExpenseLogEntry _toLog(Map<String, Object?> r) => ExpenseLogEntry(
        id: r['id'] as int,
        expenseId: r['expense_id'] as int,
        action: expenseLogActionFromName(r['action'] as String),
        actor: (r['actor'] as String?) ?? '',
        at: parseDbTime(r['logged_at']),
        before: _decode(r['before_json']),
        after: _decode(r['after_json']),
      );

  @override
  Stream<List<Expense>> watchMonth(int year, int month) {
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    return _db.watch(() async {
      final rows = await _db.raw.query(
        'expenses',
        where: 'is_deleted = 0 AND substr(expense_date, 1, 7) = ?',
        whereArgs: [prefix],
        orderBy: 'expense_date DESC, id DESC',
      );
      return rows.map(_toExpense).toList();
    });
  }

  @override
  Stream<List<ExpenseLogEntry>> watchLog({int limit = 300}) {
    return _db.watch(() async {
      final rows = await _db.raw.query(
        'expense_log',
        orderBy: 'logged_at DESC, id DESC',
        limit: limit,
      );
      return rows.map(_toLog).toList();
    });
  }

  @override
  Stream<List<String>> watchWithdrawerNames() {
    return _db.watch(() async {
      final rows = await _db.raw.rawQuery('''
        SELECT withdrawer, MAX(expense_date) AS last_date
        FROM expenses
        WHERE kind = 'withdrawals' AND is_deleted = 0
          AND withdrawer IS NOT NULL AND withdrawer != ''
        GROUP BY withdrawer
        ORDER BY last_date DESC
        LIMIT 20
      ''');
      return [for (final r in rows) r['withdrawer'] as String];
    });
  }

  /// رفض متوقَّع (مدخلات غير صالحة...). نعيده كـ Future فاشل ولا نستعمل `throw`
  /// حتى لا يتوقف المنقّح (debugger) عند كل رفض عادي، ولا يختلط مع الأخطاء
  /// البرمجية الحقيقية. المستدعي يلتقطه بـ try/catch عادي.
  static Future<T> _rejected<T>(String message) =>
      Future<T>.error(ValidationException(message));

  static Map<String, Object?> _snapshotOfInput(ExpenseInput i) => {
        'kind': i.kind.name,
        'amount': i.amount.amount,
        'description': i.description,
        'date': formatDate(i.date),
        'withdrawer': i.withdrawer,
      };

  static Map<String, Object?> _snapshotOfRow(Map<String, Object?> r) => {
        'kind': r['kind'],
        'amount': _int(r['amount']),
        'description': (r['description'] as String?) ?? '',
        'date': formatDate(parseDbTime(r['expense_date'])),
        'withdrawer': r['withdrawer'],
      };

  /// اسم المدير الذي يُكتب في السجل.
  Future<String> _actor(DatabaseExecutor ex) async {
    final rows = await ex.query('manager_account', columns: ['username'], limit: 1);
    final name = rows.isEmpty ? null : (rows.first['username'] as String?)?.trim();
    return (name == null || name.isEmpty) ? 'المدير' : name;
  }

  Future<void> _log(
    DatabaseExecutor ex, {
    required int expenseId,
    required ExpenseLogAction action,
    required String actor,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) async {
    await ex.insert('expense_log', {
      'expense_id': expenseId,
      'action': action.dbName,
      'actor': actor,
      'logged_at': dbTime(DateTime.now()),
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': after == null ? null : jsonEncode(after),
    });
  }

  @override
  Future<int> add(ExpenseInput input) {
    final error = input.validate();
    if (error != null) return _rejected<int>(error);
    final clean = input.sanitized();
    final now = dbTime(DateTime.now());
    return _db.write((txn) async {
      final id = await txn.insert('expenses', {
        'kind': clean.kind.name,
        'amount': clean.amount.amount,
        'description': clean.description,
        'expense_date': dbTime(clean.date),
        'withdrawer': clean.withdrawer,
        'is_deleted': 0,
        'created_at': now,
        'updated_at': now,
      });
      await _log(
        txn,
        expenseId: id,
        action: ExpenseLogAction.added,
        actor: await _actor(txn),
        after: _snapshotOfInput(clean),
      );
      return id;
    });
  }

  /// المصروف غير المحذوف، أو null إن لم يوجد.
  Future<Map<String, Object?>?> _findLive(DatabaseExecutor ex, int id) async {
    final rows = await ex.query(
      'expenses',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> update(int id, ExpenseInput input) {
    final error = input.validate();
    if (error != null) return _rejected<void>(error);
    final clean = input.sanitized();
    return _db.write<bool>((txn) async {
      final row = await _findLive(txn, id);
      if (row == null) return false;
      final before = _snapshotOfRow(row);
      final after = _snapshotOfInput(clean);
      if (mapEquals(before, after)) return true;
      await txn.update(
        'expenses',
        {
          'kind': clean.kind.name,
          'amount': clean.amount.amount,
          'description': clean.description,
          'expense_date': dbTime(clean.date),
          'withdrawer': clean.withdrawer,
          'updated_at': dbTime(DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _log(
        txn,
        expenseId: id,
        action: ExpenseLogAction.edited,
        actor: await _actor(txn),
        before: before,
        after: after,
      );
      return true;
    }).then((found) =>
        found ? Future<void>.value() : _rejected<void>(ExpenseErrors.notFound));
  }

  @override
  Future<void> delete(int id) {
    return _db.write<bool>((txn) async {
      final row = await _findLive(txn, id);
      if (row == null) return false;
      await txn.update(
        'expenses',
        {'is_deleted': 1, 'updated_at': dbTime(DateTime.now())},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _log(
        txn,
        expenseId: id,
        action: ExpenseLogAction.deleted,
        actor: await _actor(txn),
        before: _snapshotOfRow(row),
      );
      return true;
    }).then((found) =>
        found ? Future<void>.value() : _rejected<void>(ExpenseErrors.notFound));
  }
}
