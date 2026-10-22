import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/database/db_utils.dart';
import 'package:gaming_hall/core/database/schema.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/features/invoices/data/invoice_repository_impl.dart';
import 'package:gaming_hall/features/resources/data/resource_repository_impl.dart';
import 'package:gaming_hall/features/resources/domain/entities/game_resource.dart';
import 'package:gaming_hall/features/resources/domain/entities/resource_kind.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// أنواع الطاولات، التسعير بحسب الفئة، والوقت المحدد مع التمديد.
void main() {
  late AppDatabase db;
  late ResourceRepositoryImpl resources;
  late InvoiceRepositoryImpl invoices;

  GameResource ps() => GameResource(
        id: 0,
        name: 'PS 1',
        kind: ResourceKind.playstation,
        maxPlayers: 4,
        hourlyRates: const [Money(10000), Money(14000), Money(18000), Money(20000)],
      );

  GameResource table(String name, String type) => GameResource(
        id: 0,
        name: name,
        kind: ResourceKind.table,
        typeName: type,
        maxPlayers: 3, // يُصحَّح إلى 1 تلقائيًا
        hourlyRates: const [Money(8000), Money(9000), Money(9500), Money(9900)],
      );

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    resources = ResourceRepositoryImpl(db);
    invoices = InvoiceRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  group('أنواع الطاولات', () {
    test('قائمة الأنواع فارغة في البداية (لا أنواع جاهزة)', () async {
      final types = await resources.watchTypes().first;
      expect(types, isEmpty);
    });

    test('لا تُضاف طاولة بنوع غير موجود، وتُضاف بعد أن يضيف المدير النوع', () async {
      expect(() => resources.add(table('طاولة 1', 'بلياردو')), throwsA(isA<ArgumentError>()));

      await resources.addType('بلياردو');

      final t = await resources.add(table('طاولة 1', 'بلياردو'));
      expect(t.typeName, 'بلياردو');
      expect(t.typeLabel, 'بلياردو');
    });

    test('الطاولة: سعر واحد وبدون عدد لاعبين مهما أُرسل', () async {
      await resources.addType('هوكي');
      final t = await resources.add(table('هوكي 1', 'هوكي'));
      expect(t.maxPlayers, 1);
      expect(t.hourlyRates.every((r) => r.amount == 8000), isTrue);
    });

    test('النوع يبقى محفوظًا، والمكرر مرفوض، ويمكن حذفه', () async {
      final custom = await resources.addType('فوتبول طاولة');
      expect(() => resources.addType('فوتبول طاولة'), throwsA(isA<StateError>()));
      expect((await resources.watchTypes().first).map((t) => t.name), ['فوتبول طاولة']);

      await resources.removeType(custom.id);
      final after = await resources.watchTypes().first;
      expect(after.any((t) => t.name == 'فوتبول طاولة'), isFalse);
    });

    test('تعديل اسم نوع يغيّره في طاولاته، والاسم المكرر مرفوض', () async {
      final a = await resources.addType('سنوكر');
      await resources.addType('بلياردو');
      final t = await resources.add(table('سنوكر 1', 'سنوكر'));

      await resources.renameType(a.id, 'سنوكر كبير');
      final reloaded = (await resources.watchAll().first).firstWhere((r) => r.id == t.id);
      expect(reloaded.typeName, 'سنوكر كبير');
      expect((await resources.watchTypes().first).map((x) => x.name),
          containsAll(['سنوكر كبير', 'بلياردو']));

      expect(() => resources.renameType(a.id, 'بلياردو'), throwsA(isA<StateError>()));
      expect(() => resources.renameType(a.id, '  '), throwsA(isA<ArgumentError>()));
    });

    test('لا يُحذف نوع تستعمله طاولة', () async {
      final custom = await resources.addType('سنوكر');
      await resources.add(table('سنوكر 1', 'سنوكر'));
      expect(() => resources.removeType(custom.id), throwsA(isA<StateError>()));
    });

    test('البلايستيشن فقط له سعر لكل عدد لاعبين', () async {
      final r = await resources.add(ps());
      expect(r.maxPlayers, 4);
      expect(r.rateFor(2).amount, 14000);
      expect(r.kind.hasPlayerPricing, isTrue);
      expect(ResourceKind.computer.hasPlayerPricing, isFalse);
    });

    test('الكمبيوتر: سعر واحد بدون لاعبين', () async {
      final c = await resources.add(GameResource(
        id: 0,
        name: 'كمبيوتر 1',
        kind: ResourceKind.computer,
        maxPlayers: 4,
        hourlyRates: const [Money(5000), Money(6000), Money(7000), Money(8000)],
      ));
      expect(c.maxPlayers, 1);
      expect(c.rateFor(1).amount, 5000);
    });
  });

  group('الوقت المحدد', () {
    Future<(int invoiceId, GameResource res)> setup() async {
      final r = await resources.add(ps());
      final inv = await invoices.create('زبون');
      return (inv.id, r);
    }

    test('وقت محدد غير صالح مرفوض', () async {
      final (invId, r) = await setup();
      expect(
        () => invoices.startPlay(
            invoiceId: invId, resourceId: r.id, playerCount: 1, plannedMinutes: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('الوقت المحدد لا ينتهي قبل موعده، ويمكن تمديده وهو جارٍ', () async {
      final (invId, r) = await setup();
      await invoices.startPlay(
          invoiceId: invId, resourceId: r.id, playerCount: 1, plannedMinutes: 60);

      expect(await invoices.endExpiredFixedLines(), isEmpty);

      final line = (await invoices.getById(invId))!.playLines.single;
      expect(line.isFixed, isTrue);
      expect(line.plannedMinutes, 60);

      await invoices.extendPlay(playLineId: line.id, extraMinutes: 15);
      final extended = (await invoices.getById(invId))!.playLines.single;
      expect(extended.plannedMinutes, 75);
    });

    test('التمديد للوقت المفتوح مرفوض', () async {
      final (invId, r) = await setup();
      await invoices.startPlay(invoiceId: invId, resourceId: r.id, playerCount: 1);
      final line = (await invoices.getById(invId))!.playLines.single;
      expect(
        () => invoices.extendPlay(playLineId: line.id, extraMinutes: 15),
        throwsA(isA<StateError>()),
      );
    });

    test('عند انتهاء الوقت يُنهى عند نهايته بالضبط ويُحاسَب الوقت المحدد فقط', () async {
      final (invId, r) = await setup();
      await invoices.startPlay(
          invoiceId: invId, resourceId: r.id, playerCount: 1, plannedMinutes: 60);

      // نُرجع البداية ساعتين للوراء: الوقت المحدد (ساعة) انتهى منذ ساعة.
      await db.raw.update('play_lines',
          {'started_at': dbTime(DateTime.now().subtract(const Duration(hours: 2)))});

      final ended = await invoices.endExpiredFixedLines();
      expect(ended, hasLength(1));
      expect(ended.single.billedMinutes, 60);
      expect(ended.single.charge!.amount, 10000);
      expect(ended.single.isRunning, isFalse);

      // استدعاء ثانٍ لا يفعل شيئًا.
      expect(await invoices.endExpiredFixedLines(), isEmpty);
    });

    test('التمديد بعد الانتهاء يبدأ خطًا جديدًا من الآن بنفس السعر', () async {
      final (invId, r) = await setup();
      await invoices.startPlay(
          invoiceId: invId, resourceId: r.id, playerCount: 2, plannedMinutes: 30);
      await db.raw.update('play_lines',
          {'started_at': dbTime(DateTime.now().subtract(const Duration(hours: 1)))});
      await invoices.endExpiredFixedLines();

      final first = (await invoices.getById(invId))!.playLines.single;
      await invoices.extendPlay(playLineId: first.id, extraMinutes: 15);

      final lines = (await invoices.getById(invId))!.playLines;
      expect(lines, hasLength(2));
      expect(lines.last.isRunning, isTrue);
      expect(lines.last.plannedMinutes, 15);
      expect(lines.last.playerCount, 2);
      expect(lines.last.hourlyRate.amount, 14000);
      // وقت الانتظار بين الخطّين لا يُحاسَب: الخط الأول 30 دقيقة فقط.
      expect(lines.first.billedMinutes, 30);
    });

    test('المحاسبة تقصّ الوقت المحدد المنتهي ولا تحاسب بعد نهايته', () async {
      final (invId, r) = await setup();
      await invoices.startPlay(
          invoiceId: invId, resourceId: r.id, playerCount: 1, plannedMinutes: 30);
      await db.raw.update('play_lines',
          {'started_at': dbTime(DateTime.now().subtract(const Duration(hours: 3)))});

      final closed = await invoices.checkout(invId);
      expect(closed.playLines.single.billedMinutes, 30);
      // 30 دقيقة × 10000 / ساعة = 5000 (وهو الحد الأدنى أيضًا)
      expect(closed.settledTotals!.finalTotal.amount, 5000);
    });

    test('الوقت المحدد يُوقَف مبكرًا فيُحاسَب بدقائقه الفعلية فقط', () async {
      final (invId, r) = await setup();
      await invoices.startPlay(
          invoiceId: invId, resourceId: r.id, playerCount: 1, plannedMinutes: 120);
      await db.raw.update('play_lines',
          {'started_at': dbTime(DateTime.now().subtract(const Duration(minutes: 20)))});

      final line = (await invoices.getById(invId))!.playLines.single;
      await invoices.stopPlay(line.id);
      final stopped = (await invoices.getById(invId))!.playLines.single;
      expect(stopped.billedMinutes, 20);
    });
  });

  test('ترحيل قاعدة قديمة (v1) إلى v2 يحوّل الأنواع القديمة إلى طاولات بأسمائها', () async {
    final dir = Directory.systemTemp.createTempSync('gh_migrate_');
    final path = '${dir.path}/old.db';
    try {
      sqfliteFfiInit();
      // بناء قاعدة بشكل الإصدار 1: بلا type_name ولا planned_minutes ولا resource_types.
      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, _) async {
            for (final raw in AppSchema.createStatements) {
              if (raw.contains('resource_types')) continue;
              final stmt = raw
                  .replaceAll('      type_name TEXT,\n', '')
                  .replaceAll(',\n      planned_minutes INTEGER', '')
                  .replaceAll('      is_open INTEGER NOT NULL DEFAULT 0,\n', '');
              await d.execute(stmt);
            }
          },
        ),
      );
      await v1.insert('resources', {
        'name': 'طاولة قديمة',
        'type': 'billiards',
        'max_players': 4,
        'rate1': 8000,
        'rate2': 8000,
        'rate3': 8000,
        'rate4': 8000,
        'created_at': DateTime.now().toIso8601String(),
      });
      await v1.close();

      final upgraded = await AppDatabase.open(path: path);
      final row = (await upgraded.raw.query('resources')).single;
      expect(row['type'], 'table');
      expect(row['type_name'], 'بلياردو');

      final enabled = await upgraded.raw
          .query('resource_types', where: 'name = ?', whereArgs: ['بلياردو']);
      expect(enabled.single['is_enabled'], 1);
      expect(enabled.single['is_preset'], 0);

      // الأنواع الجاهزة غير المستعملة (هوكي، بينغ بونغ) حُذفت في الإصدار 3.
      final all = await upgraded.raw.query('resource_types');
      expect(all.map((r) => r['name']), ['بلياردو']);
      await upgraded.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
