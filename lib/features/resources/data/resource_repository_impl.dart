import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/domain/value_objects/money.dart';
import '../domain/entities/game_resource.dart';
import '../domain/entities/resource_kind.dart';
import '../domain/entities/resource_type.dart';
import '../domain/repositories/resource_repository.dart';

GameResource resourceFromRow(Map<String, Object?> r) {
  return GameResource(
    id: r['id'] as int,
    name: r['name'] as String,
    kind: resourceKindFromName(r['type'] as String),
    typeName: r['type_name'] as String?,
    maxPlayers: r['max_players'] as int,
    hourlyRates: [
      Money(r['rate1'] as int),
      Money(r['rate2'] as int),
      Money(r['rate3'] as int),
      Money(r['rate4'] as int),
    ],
    outOfService: dbBool(r['out_of_service']),
    isActive: dbBool(r['is_active']),
  );
}

class ResourceRepositoryImpl implements ResourceRepository {
  final AppDatabase _db;
  ResourceRepositoryImpl(this._db);

  Future<List<GameResource>> _loadAll() async {
    final rows = await _db.raw.query(
      'resources',
      where: 'is_active = 1',
      orderBy: 'id ASC',
    );
    return rows.map(resourceFromRow).toList();
  }

  @override
  Stream<List<GameResource>> watchAll() => _db.watch(_loadAll);

  /// للبلايستيشن فقط: عدد لاعبين 1..4 وسعر لكل عدد. لغيره: سعر واحد وعدد
  /// اللاعبين 1 دائمًا (يُفرض هنا مهما أرسلت الواجهة).
  GameResource _normalize(GameResource r) {
    if (r.kind.hasPlayerPricing) return r;
    final rate = r.hourlyRates.first;
    return r.copyWith(
      maxPlayers: 1,
      hourlyRates: [rate, rate, rate, rate],
      typeName: r.kind == ResourceKind.table ? r.typeName?.trim() : null,
    );
  }

  Future<void> _validate(DatabaseExecutor ex, GameResource r) async {
    if (r.name.trim().isEmpty) throw ArgumentError('اسم الجهاز مطلوب');
    if (r.maxPlayers < 1 || r.maxPlayers > GameResource.maxPlayersLimit) {
      throw ArgumentError('عدد اللاعبين يجب أن يكون بين 1 و4');
    }
    for (var i = 0; i < r.maxPlayers; i++) {
      if (r.hourlyRates[i].amount <= 0) {
        throw ArgumentError(r.kind.hasPlayerPricing
            ? 'أدخل سعر الساعة للاعبين المسموحين كلهم'
            : 'أدخل سعر الساعة');
      }
    }
    if (r.kind == ResourceKind.table) {
      final type = r.typeName?.trim() ?? '';
      if (type.isEmpty) throw ArgumentError('اختر نوع الطاولة');
      final rows = await ex.query('resource_types',
          where: 'name = ? COLLATE NOCASE',
          whereArgs: [type],
          limit: 1);
      if (rows.isEmpty) {
        throw ArgumentError('نوع الطاولة غير موجود. أضفه من "أنواع الطاولات" أولًا.');
      }
    }
  }

  Map<String, Object?> _toRow(GameResource r) {
    // الأسعار فوق أقصى عدد لاعبين تُنسخ من آخر سعر مسموح (لا تُستخدم أصلًا).
    final rates = [
      for (var i = 0; i < GameResource.maxPlayersLimit; i++)
        r.hourlyRates[i < r.maxPlayers ? i : r.maxPlayers - 1].amount,
    ];
    return {
      'name': r.name.trim(),
      'type': r.kind.name,
      'type_name': r.typeName,
      'max_players': r.maxPlayers,
      'rate1': rates[0],
      'rate2': rates[1],
      'rate3': rates[2],
      'rate4': rates[3],
      'out_of_service': boolToDb(r.outOfService),
    };
  }

  @override
  Future<GameResource> add(GameResource input) async {
    final resource = _normalize(input);
    try {
      final id = await _db.write((txn) async {
        await _validate(txn, resource);
        return txn.insert('resources', {
          ..._toRow(resource),
          'is_active': 1,
          'created_at': dbTime(DateTime.now()),
        });
      });
      final rows = await _db.raw.query('resources', where: 'id = ?', whereArgs: [id]);
      return resourceFromRow(rows.first);
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw StateError('يوجد جهاز بنفس الاسم "${resource.name.trim()}"');
      }
      rethrow;
    }
  }

  @override
  Future<GameResource> update(GameResource input) async {
    final resource = _normalize(input);
    try {
      await _db.write((txn) async {
        await _validate(txn, resource);
        if (resource.outOfService) {
          final before = await txn.query('resources',
              columns: ['out_of_service'],
              where: 'id = ?',
              whereArgs: [resource.id],
              limit: 1);
          final wasOut = before.isNotEmpty && dbBool(before.first['out_of_service']);
          if (!wasOut) {
            final reason = await _blockReason(txn, resource.id, forDelete: false);
            if (reason != null) throw StateError(reason);
          }
        }
        await txn.update(
          'resources',
          _toRow(resource),
          where: 'id = ?',
          whereArgs: [resource.id],
        );
      });
      final rows = await _db.raw
          .query('resources', where: 'id = ?', whereArgs: [resource.id]);
      return resourceFromRow(rows.first);
    } catch (e) {
      if (isUniqueViolation(e)) {
        throw StateError('يوجد جهاز بنفس الاسم "${resource.name.trim()}"');
      }
      rethrow;
    }
  }

  /// سبب منع الحذف / الإخراج من الخدمة، أو null إن كان مسموحًا.
  /// المنع إن كان على الجهاز لعب جارٍ، أو حجز قادم (لم ينتهِ وقته ولم يُلغَ ولم يتحوّل لفاتورة).
  Future<String?> _blockReason(
    DatabaseExecutor ex,
    int id, {
    required bool forDelete,
  }) async {
    final running = await ex.rawQuery(
      'SELECT 1 FROM play_lines WHERE resource_id = ? AND ended_at IS NULL LIMIT 1',
      [id],
    );
    // الحجز القادم فقط يمنع: حالته scheduled ولم ينتهِ وقته بعد. الملغى والمتحوّل
    // لفاتورة، والذي "فات موعده" (انتهى وقته ولم يُنفَّذ)، لا يمنعون.
    final now = DateTime.now();
    final scheduled = await ex.query(
      'bookings',
      columns: ['end_at'],
      where: "resource_id = ? AND status = 'scheduled'",
      whereArgs: [id],
    );
    final booked = scheduled
        .where((row) => now.isBefore(parseDbTime(row['end_at'])))
        .toList();
    final action = forDelete ? 'حذفه' : 'إخراجه من الخدمة';
    if (running.isNotEmpty && booked.isNotEmpty) {
      return 'لا يمكن $action: عليه لعب جارٍ وعليه حجز. '
          'أنهِ اللعب وألغِ الحجز أو نفّذه أولًا.';
    }
    if (running.isNotEmpty) {
      return 'لا يمكن $action: عليه لعب جارٍ. أنهِ اللعب أولًا.';
    }
    if (booked.isNotEmpty) {
      return 'لا يمكن $action: عليه حجز قادم. ألغِ الحجز أو نفّذه أولًا.';
    }
    return null;
  }

  @override
  Future<String?> blockReason(int id, {required bool forDelete}) =>
      _blockReason(_db.raw, id, forDelete: forDelete);

  @override
  Future<void> setOutOfService(int id, bool value) async {
    await _db.write((txn) async {
      if (value) {
        final reason = await _blockReason(txn, id, forDelete: false);
        if (reason != null) throw StateError(reason);
      }
      await txn.update(
        'resources',
        {'out_of_service': boolToDb(value)},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> remove(int id) async {
    await _db.write((txn) async {
      final reason = await _blockReason(txn, id, forDelete: true);
      if (reason != null) throw StateError(reason);
      await txn.update(
        'resources',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // ------------------------------------------------------------ أنواع الطاولات

  ResourceType _typeFromRow(Map<String, Object?> r) => ResourceType(
        id: r['id'] as int,
        name: r['name'] as String,
        kind: resourceKindFromName(r['kind'] as String),
      );

  @override
  Stream<List<ResourceType>> watchTypes() => _db.watch(() async {
        final rows = await _db.raw.query('resource_types', orderBy: 'id ASC');
        return rows.map(_typeFromRow).toList();
      });

  Future<bool> _typeInUse(DatabaseExecutor ex, String name) async {
    final rows = await ex.rawQuery(
      'SELECT 1 FROM resources WHERE is_active = 1 AND type_name = ? COLLATE NOCASE LIMIT 1',
      [name],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<ResourceType> addType(String name, {ResourceKind kind = ResourceKind.table}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw ArgumentError('اسم النوع مطلوب');
    if (clean.length > 40) throw ArgumentError('اسم النوع طويل');
    try {
      final id = await _db.write((txn) => txn.insert('resource_types', {
            'name': clean,
            'kind': kind.name,
            'is_enabled': 1,
            'is_preset': 0,
            'created_at': dbTime(DateTime.now()),
          }));
      final rows = await _db.raw.query('resource_types', where: 'id = ?', whereArgs: [id]);
      return _typeFromRow(rows.first);
    } catch (e) {
      if (isUniqueViolation(e)) throw StateError('النوع \"$clean\" موجود مسبقًا');
      rethrow;
    }
  }

  @override
  Future<void> renameType(int id, String newName) async {
    final clean = newName.trim();
    if (clean.isEmpty) throw ArgumentError('اسم النوع مطلوب');
    if (clean.length > 40) throw ArgumentError('اسم النوع طويل');
    try {
      await _db.write((txn) async {
        final rows =
            await txn.query('resource_types', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) throw StateError('النوع غير موجود');
        final old = rows.first['name'] as String;
        await txn.update('resource_types', {'name': clean}, where: 'id = ?', whereArgs: [id]);
        // الطاولات تخزّن اسم النوع نصًا، فتتبع الاسم الجديد.
        await txn.update('resources', {'type_name': clean},
            where: 'type_name = ? COLLATE NOCASE', whereArgs: [old]);
      });
    } catch (e) {
      if (isUniqueViolation(e)) throw StateError('النوع "$clean" موجود مسبقًا');
      rethrow;
    }
  }

  @override
  Future<void> removeType(int id) async {
    await _db.write((txn) async {
      final rows = await txn.query('resource_types', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      if (await _typeInUse(txn, rows.first['name'] as String)) {
        throw StateError('لا يمكن حذف نوع تستعمله طاولات حاليًا.');
      }
      await txn.delete('resource_types', where: 'id = ?', whereArgs: [id]);
    });
  }
}
