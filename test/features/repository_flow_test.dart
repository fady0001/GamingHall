import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/features/auth/data/auth_repository_impl.dart';
import 'package:gaming_hall/features/auth/domain/repositories/auth_repository.dart';
import 'package:gaming_hall/features/bookings/data/booking_repository_impl.dart';
import 'package:gaming_hall/features/bookings/domain/entities/booking.dart';
import 'package:gaming_hall/features/days/data/work_day_repository_impl.dart';
import 'package:gaming_hall/features/days/domain/repositories/work_day_repository.dart';
import 'package:gaming_hall/features/invoices/data/invoice_repository_impl.dart';
import 'package:gaming_hall/features/invoices/domain/entities/invoice.dart';
import 'package:gaming_hall/features/invoices/domain/repositories/invoice_repository.dart';
import 'package:gaming_hall/features/menu/data/menu_repository_impl.dart';
import 'package:gaming_hall/features/menu/domain/entities/menu_category.dart';
import 'package:gaming_hall/features/menu/domain/entities/menu_item_entity.dart';
import 'package:gaming_hall/features/reports/data/report_repository_impl.dart';
import 'package:gaming_hall/features/reports/domain/entities/report.dart';
import 'package:gaming_hall/features/resources/data/resource_repository_impl.dart';
import 'package:gaming_hall/features/resources/domain/entities/game_resource.dart';
import 'package:gaming_hall/features/resources/domain/entities/resource_kind.dart';
import 'package:gaming_hall/features/settings/data/settings_repository_impl.dart';

/// اختبارات تكامل على قاعدة SQLite حقيقية في الذاكرة.
void main() {
  late AppDatabase db;
  late ResourceRepositoryImpl resources;
  late MenuRepositoryImpl menu;
  late InvoiceRepositoryImpl invoices;
  late WorkDayRepositoryImpl days;
  late BookingRepositoryImpl bookings;
  late SettingsRepositoryImpl settings;

  GameResource ps({String name = 'PS 1'}) => GameResource(
        id: 0,
        name: name,
        kind: ResourceKind.playstation,
        maxPlayers: 4,
        hourlyRates: const [Money(10000), Money(14000), Money(18000), Money(20000)],
      );

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    resources = ResourceRepositoryImpl(db);
    menu = MenuRepositoryImpl(db);
    invoices = InvoiceRepositoryImpl(db);
    days = WorkDayRepositoryImpl(db);
    bookings = BookingRepositoryImpl(db);
    settings = SettingsRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  group('الموارد والمنيو', () {
    test('إضافة جهاز واسمه فريد (بدون حساسية لحالة الأحرف)', () async {
      await resources.add(ps(name: 'PS 1'));
      expect(() => resources.add(ps(name: 'ps 1')), throwsA(isA<StateError>()));
    });

    test('السعر يختلف حسب عدد اللاعبين', () async {
      final r = await resources.add(ps());
      expect(r.rateFor(1).amount, 10000);
      expect(r.rateFor(3).amount, 18000);
    });

    test('حذف جهاز عليه لعب جارٍ مرفوض، وإخراجه من الخدمة مرفوض', () async {
      final r = await resources.add(ps());
      final inv = await invoices.create('أحمد');
      await invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 2);
      expect(() => resources.remove(r.id), throwsA(isA<StateError>()));
      expect(() => resources.setOutOfService(r.id, true), throwsA(isA<StateError>()));
    });

    test('صنف المنيو: اسم فريد وسعر موجب', () async {
      await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      expect(
        () => menu.add(const MenuItemEntity(
            id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(1500))),
        throwsA(isA<StateError>()),
      );
      expect(
        () => menu.add(const MenuItemEntity(
            id: 0, name: 'ماء', category: MenuCategory.coldDrinks, price: Money(0))),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('الفاتورة', () {
    test('جهاز واحد لا يعمل في لعبين جاريين معًا', () async {
      final r = await resources.add(ps());
      final a = await invoices.create('أحمد');
      final b = await invoices.create('سامر');
      await invoices.startPlay(invoiceId: a.id, resourceId: r.id, playerCount: 1);
      expect(
        () => invoices.startPlay(invoiceId: b.id, resourceId: r.id, playerCount: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('جهاز خارج الخدمة لا يبدأ عليه لعب، وعدد اللاعبين ضمن الحد', () async {
      final r = await resources.add(ps());
      await resources.setOutOfService(r.id, true);
      final inv = await invoices.create('أحمد');
      expect(
        () => invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 1),
        throwsA(isA<StateError>()),
      );
      await resources.setOutOfService(r.id, false);
      expect(
        () => invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 5),
        throwsA(isA<StateError>()),
      );
    });

    test('سعر الساعة يُثبَّت وقت البدء حتى لو تغيّر السعر لاحقًا', () async {
      final r = await resources.add(ps());
      final inv = await invoices.create('أحمد');
      await invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 2);
      await resources.update(r.copyWith(hourlyRates: const [
        Money(99000), Money(99000), Money(99000), Money(99000),
      ]));
      final loaded = (await invoices.getById(inv.id))!;
      expect(loaded.playLines.single.hourlyRate.amount, 14000);
      expect(loaded.playLines.single.playerCount, 2);
    });

    test('المحاسبة: لعب لحظي + صنف صغير = الحد الأدنى 5000', () async {
      final r = await resources.add(ps());
      final tea = await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      final inv = await invoices.create('أحمد');
      await invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 1);
      await invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 1);

      final closed = await invoices.checkout(inv.id);
      expect(closed.status, InvoiceStatus.closed);
      expect(closed.runningLines, isEmpty);
      expect(closed.settledTotals!.finalTotal.amount, 5000);
      expect(closed.settledTotals!.minimumAdjustment.amount, 3000);
    });

    test('المحاسبة: مشتريات كبيرة تتجاوز الحد الأدنى', () async {
      final meal = await menu.add(const MenuItemEntity(
          id: 0, name: 'وجبة', category: MenuCategory.food, price: Money(12000)));
      final inv = await invoices.create('أحمد');
      await invoices.addItem(invoiceId: inv.id, menuItemId: meal.id, quantity: 2);
      final closed = await invoices.checkout(inv.id);
      expect(closed.settledTotals!.finalTotal.amount, 24000);
      expect(closed.settledTotals!.minimumAdjustment.amount, 0);
    });

    test('إضافة نفس الصنف مرتين تزيد الكمية، والصفر يحذفه', () async {
      final tea = await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      final inv = await invoices.create('أحمد');
      await invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 1);
      await invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 2);
      var loaded = (await invoices.getById(inv.id))!;
      expect(loaded.itemLines.single.quantity, 3);

      await invoices.setItemQuantity(loaded.itemLines.single.id, 0);
      loaded = (await invoices.getById(inv.id))!;
      expect(loaded.itemLines, isEmpty);
    });

    test('سعر الصنف يُثبَّت في الفاتورة حتى لو تغيّر في المنيو', () async {
      final tea = await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      final inv = await invoices.create('أحمد');
      await invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 1);
      await menu.update(tea.copyWith(price: const Money(9000)));
      final loaded = (await invoices.getById(inv.id))!;
      expect(loaded.itemLines.single.unitPrice.amount, 2000);
    });

    test('فاتورة فارغة لا تُحاسَب، ويمكن حذفها فقط وهي فارغة', () async {
      final inv = await invoices.create('أحمد');
      expect(() => invoices.checkout(inv.id), throwsA(isA<StateError>()));
      await invoices.deleteIfEmpty(inv.id);
      expect(await invoices.getById(inv.id), isNull);

      final tea = await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      final inv2 = await invoices.create('سامر');
      await invoices.addItem(invoiceId: inv2.id, menuItemId: tea.id, quantity: 1);
      expect(() => invoices.deleteIfEmpty(inv2.id), throwsA(isA<StateError>()));
    });

    test('الفاتورة المغلقة لا تقبل أي تعديل', () async {
      final tea = await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      final inv = await invoices.create('أحمد');
      await invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 1);
      final closed = await invoices.checkout(inv.id);

      expect(() => invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 1),
          throwsA(isA<StateError>()));
      expect(() => invoices.setItemQuantity(closed.itemLines.single.id, 5),
          throwsA(isA<StateError>()));
      expect(() => invoices.checkout(inv.id), throwsA(isA<StateError>()));
    });

    test('اسم الزبون مطلوب', () async {
      expect(() => invoices.create('   '), throwsA(isA<ArgumentError>()));
    });

    test('البحث بالاسم (عربي مُطبَّع) وبرقم الفاتورة', () async {
      final a = await invoices.create('أحمد');
      await invoices.create('سامر');
      final byName = await invoices.search(const InvoiceSearchFilter(query: 'احمد'));
      expect(byName.map((i) => i.id), [a.id]);
      final byId = await invoices.search(InvoiceSearchFilter(query: '#${a.id}'));
      expect(byId.map((i) => i.id), [a.id]);
    });
  });

  group('أيام العمل', () {
    test('يوم جديد مرفوض وفيه فواتير مفتوحة، ومسموح بعد إغلاقها', () async {
      final day1 = await days.currentDay();
      final tea = await menu.add(const MenuItemEntity(
          id: 0, name: 'شاي', category: MenuCategory.hotDrinks, price: Money(2000)));
      final inv = await invoices.create('أحمد');
      await invoices.addItem(invoiceId: inv.id, menuItemId: tea.id, quantity: 1);

      expect(() => days.startNewDay(), throwsA(isA<OpenInvoicesException>()));

      await invoices.checkout(inv.id);
      final day2 = await days.startNewDay();
      expect(day2.id, isNot(day1.id));
      expect((await days.currentDay()).id, day2.id);

      // فاتورة اليوم القديم تبقى في سجله.
      final old = await invoices.search(InvoiceSearchFilter(dayId: day1.id));
      expect(old.map((i) => i.id), [inv.id]);
      final fresh = await invoices.create('سامر');
      expect(fresh.dayId, day2.id);
    });
  });

  group('الحجوزات', () {
    DateTime soon(int minutes) => DateTime.now().add(Duration(minutes: minutes));

    test('تعارض حجزين على نفس الجهاز مرفوض، ولجهاز آخر مقبول', () async {
      final r1 = await resources.add(ps(name: 'PS 1'));
      final r2 = await resources.add(ps(name: 'PS 2'));
      await bookings.create(
        customerName: 'أحمد', phone: '0912345678', resourceId: r1.id, playerCount: 1,
        startAt: soon(60), endAt: soon(120),
      );
      expect(
        () => bookings.create(
          customerName: 'سامر', phone: '0912345678', resourceId: r1.id, playerCount: 1,
          startAt: soon(90), endAt: soon(150),
        ),
        throwsA(isA<BookingConflictException>()),
      );
      await bookings.create(
        customerName: 'سامر', phone: '0912345678', resourceId: r2.id, playerCount: 1,
        startAt: soon(90), endAt: soon(150),
      );
    });

    test('حجز في الماضي أو بمدة سالبة مرفوض', () async {
      final r = await resources.add(ps());
      expect(
        () => bookings.create(
          customerName: 'أحمد', phone: '0912345678', resourceId: r.id, playerCount: 1,
          startAt: soon(-60), endAt: soon(-30),
        ),
        throwsA(isA<BookingValidationException>()),
      );
      expect(
        () => bookings.create(
          customerName: 'أحمد', phone: '0912345678', resourceId: r.id, playerCount: 1,
          startAt: soon(60), endAt: soon(30),
        ),
        throwsA(isA<BookingValidationException>()),
      );
    });

    test('تحويل الحجز إلى فاتورة يبدأ اللعب ويُغلق الحجز', () async {
      final r = await resources.add(ps());
      final b = await bookings.create(
        customerName: 'أحمد', phone: '0912345678', resourceId: r.id, playerCount: 3,
        startAt: soon(5), endAt: soon(65),
      );
      final invoiceId = await bookings.convertToInvoice(b.id);
      final inv = (await invoices.getById(invoiceId))!;
      expect(inv.customerName, 'أحمد');
      expect(inv.runningLines.single.playerCount, 3);
      expect(inv.runningLines.single.hourlyRate.amount, 18000);

      final all = await db.raw.query('bookings');
      expect(all.single['status'], 'converted');
      expect(all.single['converted_invoice_id'], invoiceId);

      // لا يمكن تحويله مرتين.
      expect(() => bookings.convertToInvoice(b.id), throwsA(isA<StateError>()));
    });

    test('تحويل حجز على جهاز مشغول يفشل ولا يترك فاتورة يتيمة', () async {
      final r = await resources.add(ps());
      final other = await invoices.create('زبون آخر');
      await invoices.startPlay(invoiceId: other.id, resourceId: r.id, playerCount: 1);

      final b = await bookings.create(
        customerName: 'أحمد', phone: '0912345678', resourceId: r.id, playerCount: 1,
        startAt: soon(5), endAt: soon(65),
      );
      expect(() => bookings.convertToInvoice(b.id), throwsA(isA<StateError>()));

      final rows = await db.raw.query('invoices');
      expect(rows.length, 1); // فاتورة الزبون الآخر فقط
      final booking = await db.raw.query('bookings');
      expect(booking.single['status'], 'scheduled');
    });
  });

  group('منع تضارب الحجوزات مع اللعب', () {
    DateTime soon(int minutes) => DateTime.now().add(Duration(minutes: minutes));

    Future<void> book(int resourceId, DateTime s, DateTime e) => bookings.create(
          customerName: 'حاجز', phone: '0912345678', resourceId: resourceId, playerCount: 1,
          startAt: s, endAt: e,
        );

    test('لعب مفتوح مرفوض إن كان هناك حجز يبدأ خلال ساعة', () async {
      final r = await resources.add(ps());
      await book(r.id, soon(30), soon(90));
      final inv = await invoices.create('أحمد');
      expect(
        () => invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('وقت محدد ينتهي قبل الحجز مقبول، وما يتجاوزه مرفوض', () async {
      final r = await resources.add(ps());
      await book(r.id, soon(40), soon(100));
      final inv = await invoices.create('أحمد');
      expect(
        () => invoices.startPlay(
            invoiceId: inv.id, resourceId: r.id, playerCount: 1, plannedMinutes: 60),
        throwsA(isA<StateError>()),
      );
      await invoices.startPlay(
          invoiceId: inv.id, resourceId: r.id, playerCount: 1, plannedMinutes: 30);
    });

    test('حجز جارٍ الآن يمنع اللعب حتى لو الوقت المحدد قصير', () async {
      final r = await resources.add(ps());
      await book(r.id, DateTime.now(), soon(60));
      final inv = await invoices.create('أحمد');
      expect(
        () => invoices.startPlay(
            invoiceId: inv.id, resourceId: r.id, playerCount: 1, plannedMinutes: 10),
        throwsA(isA<StateError>()),
      );
    });

    test('الحجز الملغى أو بجهاز آخر لا يمنع اللعب', () async {
      final r1 = await resources.add(ps(name: 'PS 1'));
      final r2 = await resources.add(ps(name: 'PS 2'));
      await book(r2.id, soon(10), soon(70));
      await book(r1.id, soon(10), soon(70));
      final all = await db.raw.query('bookings', where: 'resource_id = ?', whereArgs: [r1.id]);
      await bookings.cancel(all.single['id'] as int);

      final inv = await invoices.create('أحمد');
      await invoices.startPlay(invoiceId: inv.id, resourceId: r1.id, playerCount: 1);
    });

    test('حجز جديد يتداخل مع لعب بوقت محدد جارٍ مرفوض، وبعد نهايته مقبول', () async {
      final r = await resources.add(ps());
      final inv = await invoices.create('أحمد');
      await invoices.startPlay(
          invoiceId: inv.id, resourceId: r.id, playerCount: 1, plannedMinutes: 60);
      expect(() => book(r.id, soon(30), soon(90)),
          throwsA(isA<BookingValidationException>()));
      await book(r.id, soon(70), soon(100));
    });

    test('حجز يبدأ الآن مرفوض أثناء لعب مفتوح جارٍ، والحجز المستقبلي مقبول', () async {
      final r = await resources.add(ps());
      final inv = await invoices.create('أحمد');
      await invoices.startPlay(invoiceId: inv.id, resourceId: r.id, playerCount: 1);
      expect(() => book(r.id, DateTime.now(), soon(60)),
          throwsA(isA<BookingValidationException>()));
      await book(r.id, soon(120), soon(180));
    });

    test('التمديد يُرفض إن وصل لوقت حجز، ويُقبل ضمن الوقت الفارغ', () async {
      final r = await resources.add(ps());
      final inv = await invoices.create('أحمد');
      await invoices.startPlay(
          invoiceId: inv.id, resourceId: r.id, playerCount: 1, plannedMinutes: 30);
      await book(r.id, soon(40), soon(100));

      final line = (await invoices.getById(inv.id))!.playLines.single;
      expect(() => invoices.extendPlay(playLineId: line.id, extraMinutes: 20),
          throwsA(isA<StateError>()));
      await invoices.extendPlay(playLineId: line.id, extraMinutes: 5);
    });

    test('تحويل حجز لفاتورة لا يتعارض مع نفسه ولا مع حجز متلاصق بعده', () async {
      final r = await resources.add(ps());
      final a = await bookings.create(
        customerName: 'أحمد', phone: '0912345678', resourceId: r.id, playerCount: 1,
        startAt: soon(5), endAt: soon(30),
      );
      await book(r.id, soon(30), soon(90)); // يبدأ لحظة نهاية الأول
      final invoiceId = await bookings.convertToInvoice(a.id);
      expect((await invoices.getById(invoiceId))!.runningLines, hasLength(1));
    });
  });

  group('الإعدادات والتقارير', () {
    test('الحد الأدنى الافتراضي 5000 ويمكن تغييره', () async {
      var s = await settings.load();
      expect(s.minimumInvoice.amount, 5000);
      await settings.save(s.copyWith(minimumInvoice: const Money(8000), loungeName: 'صالتي'));
      s = await settings.load();
      expect(s.minimumInvoice.amount, 8000);
      expect(s.loungeName, 'صالتي');
    });

    test('اسم الصالة الفارغ مرفوض', () async {
      final s = await settings.load();
      expect(() => settings.save(s.copyWith(loungeName: '  ')), throwsA(isA<ArgumentError>()));
    });

    test('تقرير: المبيعات من الفواتير المغلقة فقط', () async {
      final r = await resources.add(ps());
      final meal = await menu.add(const MenuItemEntity(
          id: 0, name: 'وجبة', category: MenuCategory.food, price: Money(12000)));

      final closedInv = await invoices.create('أحمد');
      await invoices.startPlay(invoiceId: closedInv.id, resourceId: r.id, playerCount: 1);
      await invoices.addItem(invoiceId: closedInv.id, menuItemId: meal.id, quantity: 1);
      await invoices.checkout(closedInv.id);

      final openInv = await invoices.create('سامر');
      await invoices.addItem(invoiceId: openInv.id, menuItemId: meal.id, quantity: 5);

      final now = DateTime.now();
      final report = await ReportRepositoryImpl(db).build(DateRange(
        DateTime(now.year, now.month, now.day),
        DateTime(now.year, now.month, now.day + 1),
      ));
      expect(report.summary.invoiceCount, 1);
      expect(report.summary.revenue, 12000);
      expect(report.topItemsByQuantity.single.name, 'وجبة');
      expect(report.topItemsByQuantity.single.quantity, 1);
    });
  });

  group('حساب المدير', () {
    test('إنشاء، دخول، قفل مؤقت، تغيير كلمة السر، واسترداد', () async {
      final auth = AuthRepositoryImpl(db);
      expect(await auth.hasManagerAccount(), isFalse);

      // قواعد التحقق
      expect(() => auth.createManagerAccount(username: 'ab', password: 'secret1'),
          throwsA(isA<AuthException>()));
      expect(() => auth.createManagerAccount(username: 'admin', password: '123'),
          throwsA(isA<AuthException>()));

      final code = await auth.createManagerAccount(username: 'admin', password: 'secret1');
      expect(await auth.hasManagerAccount(), isTrue);
      expect(() => auth.createManagerAccount(username: 'x2x', password: 'secret1'),
          throwsA(isA<AuthException>()));

      // كلمة السر لا تُخزَّن كما هي.
      final row = (await db.raw.query('manager_account')).single;
      expect((row['password_hash'] as String).contains('secret1'), isFalse);
      expect((row['recovery_hash'] as String).contains(code.replaceAll('-', '')), isFalse);

      // دخول صحيح (الاسم غير حساس لحالة الأحرف).
      expect((await auth.login(username: 'ADMIN', password: 'secret1')).success, isTrue);

      // تغيير كلمة السر
      await auth.changePassword(currentPassword: 'secret1', newPassword: 'newpass22');
      expect((await auth.login(username: 'admin', password: 'secret1')).success, isFalse);
      expect((await auth.login(username: 'admin', password: 'newpass22')).success, isTrue);

      // استرداد برمز الاسترداد يغيّر الرمز أيضًا
      final newCode = await auth.resetWithRecoveryCode(
          recoveryCode: code.toLowerCase(), newPassword: 'third-pass');
      expect(newCode, isNot(code));
      expect((await auth.login(username: 'admin', password: 'third-pass')).success, isTrue);
      expect(() => auth.resetWithRecoveryCode(recoveryCode: code, newPassword: 'zzzzzz'),
          throwsA(isA<AuthException>()));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('5 محاولات خاطئة تقفل الحساب مؤقتًا حتى مع كلمة السر الصحيحة', () async {
      final auth = AuthRepositoryImpl(db);
      await auth.createManagerAccount(username: 'admin', password: 'secret1');

      LoginOutcome last = const LoginOutcome(success: true);
      for (var i = 0; i < 5; i++) {
        last = await auth.login(username: 'admin', password: 'wrong$i');
        expect(last.success, isFalse);
      }
      expect(last.isLocked, isTrue);

      final correctButLocked = await auth.login(username: 'admin', password: 'secret1');
      expect(correctButLocked.success, isFalse);
      expect(correctButLocked.isLocked, isTrue);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

