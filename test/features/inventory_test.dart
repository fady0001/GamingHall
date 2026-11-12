import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/features/inventory/data/inventory_repository_impl.dart';
import 'package:gaming_hall/features/inventory/domain/entities/inventory_models.dart';
import 'package:gaming_hall/features/invoices/data/invoice_repository_impl.dart';
import 'package:gaming_hall/features/menu/data/menu_repository_impl.dart';
import 'package:gaming_hall/features/menu/domain/entities/menu_category.dart';
import 'package:gaming_hall/features/menu/domain/entities/menu_item_entity.dart';

/// اختبارات المخزون وفواتير المشتريات والجرد والتعديل اليدوي (SQLite حقيقية).
void main() {
  late AppDatabase db;
  late MenuRepositoryImpl menu;
  late InvoiceRepositoryImpl invoices;
  late InventoryRepositoryImpl inventory;
  late MenuItemEntity pepsi;

  Future<StockRow> row(int id) async =>
      (await inventory.watchStock().first).firstWhere((r) => r.itemId == id);

  PurchaseLineInput packLine(int itemId, int packs, int per, int price) =>
      PurchaseLineInput(
        itemId: itemId,
        mode: PurchaseMode.pack,
        quantity: packs,
        piecesPerPack: per,
        price: Money(price),
      );

  Future<int> buy(
    List<PurchaseLineInput> lines, {
    int paid = 0,
    int discount = 0,
    DateTime? at,
  }) => inventory.saveInvoice(
    PurchaseInvoiceInput(
      purchasedAt: at ?? DateTime(2026, 11, 2, 10),
      lines: lines,
      discount: Money(discount),
      initialPaid: Money(paid),
    ),
  );

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    menu = MenuRepositoryImpl(db);
    invoices = InvoiceRepositoryImpl(db);
    inventory = InventoryRepositoryImpl(db);
    pepsi = await menu.add(
      const MenuItemEntity(
        id: 0,
        name: 'بيبسي',
        category: MenuCategory.coldDrinks,
        price: Money(10000),
      ),
    );
  });

  tearDown(() async => db.close());

  group('حساب سطر الشراء', () {
    test('بالطرد', () {
      final c = packLine(1, 2, 24, 60000).calc();
      expect(c.totalPieces, 48);
      expect(c.unitCost.amount, 2500);
      expect(c.totalCost.amount, 120000);
    });

    test('بالقطعة بسعر القطعة', () {
      final c = const PurchaseLineInput(
        itemId: 1,
        mode: PurchaseMode.pieceUnitPrice,
        quantity: 10,
        price: Money(3000),
      ).calc();
      expect(c.totalPieces, 10);
      expect(c.unitCost.amount, 3000);
      expect(c.totalCost.amount, 30000);
    });

    test('بالقطعة بسعر إجمالي: سعر القطعة = الإجمالي ÷ العدد', () {
      final c = const PurchaseLineInput(
        itemId: 1,
        mode: PurchaseMode.pieceTotalPrice,
        quantity: 3,
        price: Money(10000),
      ).calc();
      expect(c.unitCost.amount, 3333);
      expect(c.totalCost.amount, 10000); // الإجمالي المدفوع بلا تقريب
    });

    test('أرقام غير صالحة تُرفض', () {
      expect(
        () => packLine(1, 0, 24, 1000).calc(),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => packLine(1, 1, 0, 1000).calc(),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => packLine(1, 1, 24, 0).calc(), throwsA(isA<ArgumentError>()));
    });
  });

  group('فواتير المشتريات', () {
    test('فاتورة بعدة أصناف تزيد المخزون وتحدّث التكلفة', () async {
      final cups = await inventory.createStockItem(
        name: 'كاسات',
        category: MenuCategory.other,
      );
      await buy([
        packLine(pepsi.id, 2, 24, 60000),
        PurchaseLineInput(
          itemId: cups,
          mode: PurchaseMode.pieceUnitPrice,
          quantity: 100,
          price: const Money(500),
        ),
      ]);

      expect((await row(pepsi.id)).onHand, 48);
      expect((await row(pepsi.id)).unitCost.amount, 2500);
      expect((await row(cups)).onHand, 100);

      final inv = (await inventory.watchPurchaseInvoices().first).single;
      expect(inv.lines.length, 2);
      expect(inv.itemsTotal.amount, 120000 + 50000);
    });

    test('حالة الدفع: غير مدفوعة / جزئي / كاملة، وتسديد دفعة', () async {
      final id = await buy([packLine(pepsi.id, 1, 24, 48000)]);
      var inv = (await inventory.watchPurchaseInvoices().first).single;
      expect(inv.status, PaymentStatus.unpaid);
      expect(inv.remaining.amount, 48000);

      await inventory.addPayment(invoiceId: id, amount: const Money(20000));
      inv = (await inventory.watchPurchaseInvoices().first).single;
      expect(inv.status, PaymentStatus.partial);
      expect(inv.remaining.amount, 28000);

      expect(
        () => inventory.addPayment(invoiceId: id, amount: const Money(30000)),
        throwsA(isA<StateError>()),
      );

      await inventory.addPayment(invoiceId: id, amount: const Money(28000));
      inv = (await inventory.watchPurchaseInvoices().first).single;
      expect(inv.status, PaymentStatus.paid);
    });

    test('الخصم يُنقص المطلوب دفعه', () async {
      await buy(
        [packLine(pepsi.id, 1, 24, 48000)],
        discount: 3000,
        paid: 45000,
      );
      final inv = (await inventory.watchPurchaseInvoices().first).single;
      expect(inv.payable.amount, 45000);
      expect(inv.status, PaymentStatus.paid);
    });

    test('تعديل الفاتورة يعيد حساب المخزون', () async {
      final id = await buy([packLine(pepsi.id, 1, 24, 48000)], paid: 48000);
      expect((await row(pepsi.id)).onHand, 24);

      await inventory.saveInvoice(
        PurchaseInvoiceInput(
          id: id,
          purchasedAt: DateTime(2026, 11, 2, 10),
          lines: [packLine(pepsi.id, 2, 12, 30000)],
        ),
      );
      final r = await row(pepsi.id);
      expect(r.onHand, 24); // 2 × 12
      expect(r.unitCost.amount, 2500);
      expect(
        (await inventory.watchPurchaseInvoices().first).single.lines.length,
        1,
      );
    });

    test('حذف الفاتورة يسحب قطعها من المخزون', () async {
      final id = await buy([packLine(pepsi.id, 1, 12, 24000)]);
      await inventory.deleteInvoice(id);
      expect((await row(pepsi.id)).onHand, 0);
      expect(await inventory.watchPurchaseInvoices().first, isEmpty);
    });

    test('فاتورة بلا أصناف أو بدفع أكبر من قيمتها تُرفض', () async {
      expect(() => buy([]), throwsA(isA<ArgumentError>()));
      expect(
        () => buy([packLine(pepsi.id, 1, 12, 24000)], paid: 30000),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('أصناف لا تُباع', () {
    test('لا تظهر في قائمة المشتريات ولا يمكن إضافتها لفاتورة بيع', () async {
      final cups = await inventory.createStockItem(
        name: 'كاسات',
        category: MenuCategory.other,
      );
      final menuItems = await menu.watchAll().first;
      expect(menuItems.map((i) => i.id), isNot(contains(cups)));

      final inv = await invoices.create('أحمد');
      expect(
        () =>
            invoices.addItem(invoiceId: inv.id, menuItemId: cups, quantity: 1),
        throwsA(isA<StateError>()),
      );

      // لكنها في المخزون
      expect((await row(cups)).isSellable, isFalse);
    });

    test('تفعيل "يُباع" يظهرها في المنيو بسعرها', () async {
      final cups = await inventory.createStockItem(
        name: 'مياه صغيرة',
        category: MenuCategory.coldDrinks,
      );
      await inventory.updateStockSettings(
        itemId: cups,
        trackStock: true,
        minStock: 0,
        isSellable: true,
        price: const Money(2000),
      );
      final menuItems = await menu.watchAll().first;
      expect(
        menuItems.any((i) => i.id == cups && i.price.amount == 2000),
        isTrue,
      );
    });

    test(
      'إضافة صنف بنفس الاسم من المنيو تحوّل الصنف المخفي بدل رفضه',
      () async {
        final id = await inventory.createStockItem(
          name: 'شيبس',
          category: MenuCategory.food,
        );
        final added = await menu.add(
          const MenuItemEntity(
            id: 0,
            name: 'شيبس',
            category: MenuCategory.food,
            price: Money(5000),
          ),
        );
        expect(added.id, id);
        expect((await row(id)).isSellable, isTrue);
      },
    );

    test('تفعيل "يُباع" بدون سعر يُرفض', () async {
      final id = await inventory.createStockItem(
        name: 'علبة',
        category: MenuCategory.other,
      );
      expect(
        () => inventory.updateStockSettings(
          itemId: id,
          trackStock: true,
          minStock: 0,
          isSellable: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('المخزون والمبيعات', () {
    test('ما بيع قبل بدء التتبّع لا يُخصم', () async {
      final inv = await invoices.create('أحمد');
      await invoices.addItem(
        invoiceId: inv.id,
        menuItemId: pepsi.id,
        quantity: 5,
      );

      await buy([packLine(pepsi.id, 1, 24, 48000)]);
      expect((await row(pepsi.id)).onHand, 24);

      await invoices.addItem(
        invoiceId: inv.id,
        menuItemId: pepsi.id,
        quantity: 4,
      );
      expect((await row(pepsi.id)).onHand, 20);
    });

    test('تحذير النقص: منخفض عند الحد ونفد عند الصفر', () async {
      await buy([packLine(pepsi.id, 1, 6, 12000)]);
      await inventory.updateStockSettings(
        itemId: pepsi.id,
        trackStock: true,
        minStock: 6,
        isSellable: true,
        price: const Money(10000),
      );
      expect((await row(pepsi.id)).isLow, isTrue);

      final inv = await invoices.create('سامر');
      await invoices.addItem(
        invoiceId: inv.id,
        menuItemId: pepsi.id,
        quantity: 6,
      );
      expect((await row(pepsi.id)).isOut, isTrue);
    });
  });

  group('التعديل اليدوي', () {
    setUp(() async => buy([packLine(pepsi.id, 1, 24, 48000)]));

    test('زيادة ونقص وضبط على رقم، مع تسجيل السبب', () async {
      await inventory.adjustStock(
        itemId: pepsi.id,
        mode: StockAdjustMode.decrease,
        quantity: 4,
        reason: 'تلف',
      );
      expect((await row(pepsi.id)).onHand, 20);

      await inventory.adjustStock(
        itemId: pepsi.id,
        mode: StockAdjustMode.increase,
        quantity: 3,
        reason: 'هدية',
      );
      expect((await row(pepsi.id)).onHand, 23);

      await inventory.adjustStock(
        itemId: pepsi.id,
        mode: StockAdjustMode.setTo,
        quantity: 30,
        reason: 'خطأ إدخال',
      );
      expect((await row(pepsi.id)).onHand, 30);

      final log = await inventory.watchAdjustments().first;
      expect(log.length, 3);
      expect(log.first.qty, 7); // الأحدث أولًا: 23 → 30
      expect(log.first.reason, 'خطأ إدخال');
    });

    test('السبب إلزامي', () async {
      expect(
        () => inventory.adjustStock(
          itemId: pepsi.id,
          mode: StockAdjustMode.increase,
          quantity: 1,
          reason: '  ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('الجرد', () {
    test('يسوّي المخزون ويسجّل الفرق، وإعادة الجرد في اليوم تستبدله', () async {
      await buy([packLine(pepsi.id, 1, 24, 48000)]);

      await inventory.saveCounts('2026-11-10', [CountEntry(pepsi.id, 20)]);
      var counts = await inventory.watchCounts('2026-11-10').first;
      expect(counts.single.expected, 24);
      expect(counts.single.difference, -4);
      expect((await row(pepsi.id)).onHand, 20);

      await inventory.saveCounts('2026-11-10', [CountEntry(pepsi.id, 23)]);
      counts = await inventory.watchCounts('2026-11-10').first;
      expect(counts.length, 1);
      expect(counts.single.difference, -1);
      expect((await row(pepsi.id)).onHand, 23);
    });

    test('أول جرد لصنف بلا مشتريات يحدد الكمية الابتدائية', () async {
      await inventory.saveCounts('2026-11-10', [CountEntry(pepsi.id, 30)]);
      final r = await row(pepsi.id);
      expect(r.started, isTrue);
      expect(r.onHand, 30);
    });

    test('إدخال غير صالح يُرفض', () async {
      expect(
        () => inventory.saveCounts('2026-11-10', [CountEntry(pepsi.id, -1)]),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => inventory.saveCounts('10/11/2026', [CountEntry(pepsi.id, 1)]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
