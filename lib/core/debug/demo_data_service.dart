import 'dart:convert';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../database/db_utils.dart';

/// بيانات تجريبية لتجربة التقارير والشاشات (للتطوير فقط).
///
/// كل ما يُضاف هنا يُسجَّل في جدول الإعدادات (مفتاح [_metaKey]) حتى يمكن
/// حذفه لاحقًا بدقة دون المساس ببياناتك الحقيقية.
class DemoDataService {
  final AppDatabase _db;
  DemoDataService(this._db);

  static const _metaKey = 'demo_data_meta';
  static const _tag = ' (تجريبي)';

  Future<bool> hasDemoData() async {
    final rows = await _db.raw
        .query('settings', where: 'key = ?', whereArgs: [_metaKey], limit: 1);
    return rows.isNotEmpty;
  }

  /// يضيف أجهزة وأصنافًا تجريبية + فواتير وحجوزات آخر [days] أيام + اليوم الحالي. يعيد ملخصًا نصيًا.
  Future<String> seed({int days = 10}) async {
    if (await hasDemoData()) {
      throw StateError('البيانات التجريبية موجودة مسبقًا. احذفها أولًا.');
    }
    final rnd = Random(42);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final meta = <String, dynamic>{
      'workDays': <int>[],
      'resources': <int>[],
      'menu': <int>[],
      'restoreDay': null, // {id, startedAt} لليوم المفتوح الذي عدّلنا بدايته
    };
    var invoicesCount = 0;
    var bookingsCount = 0;

    await _db.write((txn) async {
      final stamp = dbTime(now);

      // ── أجهزة تجريبية خاصة (تُضاف دائمًا وتُحذف مع البيانات التجريبية) ──
      for (final n in const ['بلياردو', 'هوكي']) {
        await txn.insert(
          'resource_types',
          {
            'name': n,
            'kind': 'table',
            'is_enabled': 1,
            'is_preset': 0,
            'created_at': stamp,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final defs = <Map<String, Object?>>[
        _res('PS 1$_tag', 'playstation', null, 4, [8000, 12000, 16000, 20000], stamp),
        _res('PS 2$_tag', 'playstation', null, 4, [8000, 12000, 16000, 20000], stamp),
        _res('كمبيوتر 1$_tag', 'computer', null, 1, [6000, 6000, 6000, 6000], stamp),
        _res('كمبيوتر 2$_tag', 'computer', null, 1, [6000, 6000, 6000, 6000], stamp),
        _res('بلياردو 1$_tag', 'table', 'بلياردو', 1, [15000, 15000, 15000, 15000], stamp),
        _res('هوكي 1$_tag', 'table', 'هوكي', 1, [10000, 10000, 10000, 10000], stamp),
      ];
      final resources = <Map<String, Object?>>[];
      for (final d in defs) {
        final id = await txn.insert('resources', d);
        (meta['resources'] as List<int>).add(id);
        resources.add({...d, 'id': id});
      }

      // ── أصناف تجريبية ──
      const items = [
        ['شاي', 'hotDrinks', 3000],
        ['قهوة', 'hotDrinks', 5000],
        ['نسكافيه', 'hotDrinks', 6000],
        ['عصير', 'coldDrinks', 8000],
        ['مياه', 'coldDrinks', 2000],
        ['كولا', 'coldDrinks', 4000],
        ['ساندويش', 'food', 12000],
        ['بطاطا', 'food', 9000],
        ['أركيلة', 'hookah', 20000],
      ];
      final menu = <Map<String, Object?>>[];
      for (final i in items) {
        final row = {
          'name': '${i[0]}$_tag',
          'category': i[1],
          'price': i[2],
          'is_active': 1,
          'created_at': stamp,
        };
        final id = await txn.insert('menu_items', row);
        (meta['menu'] as List<int>).add(id);
        menu.add({...row, 'id': id});
      }

      // ── اليوم الحالي: نبدّل بدايته إلى منتصف الليل ليظهر فيه بيانات ──
      final open = await txn.query('work_days',
          where: 'ended_at IS NULL', orderBy: 'id DESC', limit: 1);
      int? todayDayId;
      if (open.isNotEmpty) {
        todayDayId = open.first['id'] as int;
        final original = open.first['started_at'] as String;
        if (parseDbTime(original).isAfter(today)) {
          meta['restoreDay'] = {'id': todayDayId, 'startedAt': original};
          await txn.update('work_days', {'started_at': dbTime(today)},
              where: 'id = ?', whereArgs: [todayDayId]);
        }
      }

      // ── الأيام: من الأقدم إلى اليوم ──
      for (var back = days - 1; back >= 0; back--) {
        final date = DateTime(today.year, today.month, today.day - back);
        final isToday = back == 0;

        int dayId;
        if (isToday) {
          if (todayDayId == null) continue;
          dayId = todayDayId;
        } else {
          dayId = await txn.insert('work_days', {
            'started_at': dbTime(DateTime(date.year, date.month, date.day, 10)),
            'ended_at': dbTime(DateTime(date.year, date.month, date.day, 23, 59)),
          });
          (meta['workDays'] as List<int>).add(dayId);
        }

        // الجمعة والسبت أكثر ازدحامًا.
        final busy = date.weekday == DateTime.friday || date.weekday == DateTime.saturday;
        final invoiceTarget = (busy ? 11 : 6) + rnd.nextInt(5);

        // آخر لحظة مسموحة لانتهاء جلسة (اليوم الحالي: قبل الآن).
        final latestEnd = isToday
            ? now.subtract(const Duration(minutes: 5))
            : DateTime(date.year, date.month, date.day, 23, 50);
        final earliestStart = isToday
            ? DateTime(date.year, date.month, date.day, 0, 10)
            : DateTime(date.year, date.month, date.day, 11);
        if (!latestEnd.isAfter(earliestStart.add(const Duration(minutes: 40)))) continue;
        final spanMinutes = latestEnd.difference(earliestStart).inMinutes;

        for (var n = 0; n < invoiceTarget; n++) {
          final lines = 1 + (rnd.nextInt(10) == 0 ? 1 : 0);
          var play = 0;
          var minutes = 0;
          DateTime? invoiceStart;
          DateTime invoiceEnd = earliestStart;
          final lineRows = <Map<String, Object?>>[];

          for (var l = 0; l < lines; l++) {
            final r = resources[rnd.nextInt(resources.length)];
            final dur = const [30, 45, 60, 60, 90, 120, 150][rnd.nextInt(7)];
            final latestStartOffset = spanMinutes - dur;
            if (latestStartOffset <= 0) continue;
            // الذروة المسائية: نرجّح الأوقات المتأخرة.
            final skew = sqrt(rnd.nextDouble());
            final start = earliestStart
                .add(Duration(minutes: (skew * latestStartOffset).floor()));
            final end = start.add(Duration(minutes: dur));
            final type = r['type'] as String;
            final players =
                type == 'playstation' ? 1 + rnd.nextInt(r['max_players'] as int) : 1;
            final rate = r['rate$players'] as int;
            final charge = ((rate * dur / 60) / 500).round() * 500;
            lineRows.add({
              'resource_id': r['id'],
              'resource_name': r['name'],
              'resource_type': (type == 'table' ? (r['type_name'] ?? type) : type),
              'player_count': players,
              'hourly_rate': rate,
              'started_at': dbTime(start),
              'ended_at': dbTime(end),
              'billed_minutes': dur,
              'charge': charge,
              'planned_minutes': null,
            });
            play += charge;
            minutes += dur;
            if (invoiceStart == null || start.isBefore(invoiceStart)) invoiceStart = start;
            if (end.isAfter(invoiceEnd)) invoiceEnd = end;
          }
          if (lineRows.isEmpty || invoiceStart == null) continue;

          final itemRows = <Map<String, Object?>>[];
          var itemsTotal = 0;
          final itemKinds = rnd.nextInt(4); // 0..3 أصناف مختلفة
          final picked = <int>{};
          for (var k = 0; k < itemKinds; k++) {
            final m = menu[rnd.nextInt(menu.length)];
            if (!picked.add(m['id'] as int)) continue;
            final qty = 1 + rnd.nextInt(3);
            itemRows.add({
              'menu_item_id': m['id'],
              'name': m['name'],
              'category': m['category'],
              'unit_price': m['price'],
              'quantity': qty,
            });
            itemsTotal += (m['price'] as int) * qty;
          }

          final invoiceId = await txn.insert('invoices', {
            'customer_name': 'زبون ${invoicesCount + 1}$_tag',
            'day_id': dayId,
            'status': 'closed',
            'created_at': dbTime(invoiceStart),
            'closed_at': dbTime(invoiceEnd),
            'play_total': play,
            'items_total': itemsTotal,
            'minimum_adjustment': 0,
            'rounding_delta': 0,
            'final_total': play + itemsTotal,
          });
          for (final row in lineRows) {
            await txn.insert('play_lines', {...row, 'invoice_id': invoiceId});
          }
          for (final row in itemRows) {
            await txn.insert('item_lines', {...row, 'invoice_id': invoiceId});
          }
          invoicesCount++;
          // لا نستخدم minutes هنا؛ التقرير يحسبها من خطوط اللعب.
          assert(minutes >= 0);
        }

        // ── حجوزات اليوم (بعضها ملغى، والباقي محوَّل) ──
        final bookingTarget = 1 + rnd.nextInt(3);
        for (var b = 0; b < bookingTarget; b++) {
          final r = resources[rnd.nextInt(resources.length)];
          final startHour = 12 + rnd.nextInt(10);
          final start = DateTime(date.year, date.month, date.day, startHour);
          if (isToday && start.isAfter(now)) continue;
          final cancelled = rnd.nextInt(4) == 0;
          await txn.insert('bookings', {
            'customer_name': 'حجز ${bookingsCount + 1}$_tag',
            'phone': '',
            'resource_id': r['id'],
            'resource_name': r['name'],
            'player_count': 1,
            'start_at': dbTime(start),
            'end_at': dbTime(start.add(const Duration(hours: 1))),
            'status': cancelled ? 'cancelled' : 'converted',
            'is_open': 0,
            'created_at': dbTime(start.subtract(const Duration(hours: 3))),
          });
          bookingsCount++;
        }
      }

      await txn.insert(
        'settings',
        {'key': _metaKey, 'value': jsonEncode(meta)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return 'أُضيفت $invoicesCount فاتورة و$bookingsCount حجز لآخر $days يوم.';
  }

  /// يحذف كل ما أضافه [seed] فقط.
  Future<String> clear() async {
    final rows = await _db.raw
        .query('settings', where: 'key = ?', whereArgs: [_metaKey], limit: 1);
    if (rows.isEmpty) return 'لا توجد بيانات تجريبية لحذفها.';
    final meta = jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    List<int> ids(String k) => [for (final v in (meta[k] as List? ?? [])) (v as num).toInt()];

    await _db.write((txn) async {
      final inv = await txn.rawQuery(
          "SELECT id FROM invoices WHERE customer_name LIKE '%$_tag'");
      for (final r in inv) {
        final id = r['id'];
        await txn.delete('item_lines', where: 'invoice_id = ?', whereArgs: [id]);
        await txn.delete('play_lines', where: 'invoice_id = ?', whereArgs: [id]);
        await txn.delete('invoices', where: 'id = ?', whereArgs: [id]);
      }
      await txn.delete('bookings', where: "customer_name LIKE '%$_tag'");

      for (final id in ids('workDays')) {
        // نحذف اليوم فقط إن لم تبقَ عليه فواتير حقيقية.
        await txn.delete('work_days',
            where: 'id = ? AND NOT EXISTS (SELECT 1 FROM invoices WHERE day_id = ?)',
            whereArgs: [id, id]);
      }
      final restore = meta['restoreDay'];
      if (restore is Map) {
        await txn.update('work_days', {'started_at': restore['startedAt']},
            where: 'id = ?', whereArgs: [restore['id']]);
      }

      for (final id in ids('resources')) {
        final used = await txn.rawQuery(
            'SELECT (SELECT COUNT(*) FROM play_lines WHERE resource_id = ?) + '
            '(SELECT COUNT(*) FROM bookings WHERE resource_id = ?) AS c',
            [id, id]);
        if (((used.first['c'] as num?) ?? 0) == 0) {
          await txn.delete('resources', where: 'id = ?', whereArgs: [id]);
        } else {
          await txn.update('resources', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
        }
      }
      for (final id in ids('menu')) {
        final used = await txn.rawQuery(
            'SELECT COUNT(*) AS c FROM item_lines WHERE menu_item_id = ?', [id]);
        if (((used.first['c'] as num?) ?? 0) == 0) {
          await txn.delete('menu_items', where: 'id = ?', whereArgs: [id]);
        } else {
          await txn.update('menu_items', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
        }
      }
      await txn.delete('settings', where: 'key = ?', whereArgs: [_metaKey]);
    });
    return 'تم حذف البيانات التجريبية.';
  }

  static Map<String, Object?> _res(String name, String type, String? typeName,
      int maxPlayers, List<int> rates, String stamp) {
    return {
      'name': name,
      'type': type,
      'type_name': typeName,
      'max_players': maxPlayers,
      'rate1': rates[0],
      'rate2': rates[1],
      'rate3': rates[2],
      'rate4': rates[3],
      'out_of_service': 0,
      'is_active': 1,
      'created_at': stamp,
    };
  }
}
