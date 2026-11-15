import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/features/expenses/data/expense_repository_impl.dart';
import 'package:gaming_hall/features/expenses/domain/entities/expense.dart';
import 'package:gaming_hall/features/reports/data/monthly_report_pdf_builder.dart';
import 'package:gaming_hall/features/reports/data/monthly_report_repository_impl.dart';
import 'package:gaming_hall/features/reports/domain/entities/monthly_report.dart';
import 'package:gaming_hall/features/reports/domain/entities/report.dart'
    show ItemStat;
import 'package:gaming_hall/features/settings/domain/entities/app_settings.dart';

/// اختبارات التقرير الشهري (SQLite حقيقية في الذاكرة) وتوليد الـPDF.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MonthlyReportRepositoryImpl repo;
  late ExpenseRepositoryImpl expenses;

  Future<int> insert(String table, Map<String, Object?> values) =>
      db.raw.insert(table, values);

  Future<void> addExpense(ExpenseKind kind, int amount, DateTime date,
      {String? withdrawer}) async {
    await expenses.add(ExpenseInput(
      kind: kind,
      amount: Money(amount),
      description: kind == ExpenseKind.maintenance ? 'تصليح' : 'x',
      date: date,
      withdrawer: withdrawer,
    ));
  }

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    repo = MonthlyReportRepositoryImpl(db);
    expenses = ExpenseRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<void> seedOctober() async {
    const created = '2026-10-01T00:00:00.000';

    // ── المبيعات ──
    final octDay = await insert('work_days', {'started_at': '2026-10-05T10:00:00.000'});
    final novDay = await insert('work_days', {'started_at': '2026-11-01T10:00:00.000'});

    final pepsi = await insert('menu_items', {
      'name': 'بيبسي',
      'category': 'drinks',
      'price': 3000,
      'unit_cost': 1500,
      'created_at': created,
    });
    final chips = await insert('menu_items', {
      'name': 'شيبس',
      'category': 'snacks',
      'price': 1500,
      'unit_cost': 500,
      'created_at': created,
    });

    // فاتورة يوم عمل تشرين الأول أُغلقت بعد منتصف الليل (في تشرين الثاني):
    // تُحسب في تشرين الأول لأن يوم عملها بدأ فيه.
    final inv1 = await insert('invoices', {
      'customer_name': 'أ',
      'day_id': octDay,
      'status': 'closed',
      'created_at': '2026-10-05T11:00:00.000',
      'closed_at': '2026-11-01T01:00:00.000',
      'play_total': 20000,
      'items_total': 10000,
      'minimum_adjustment': 1000,
      'rounding_delta': 1000,
      'final_total': 32000,
    });
    await insert('item_lines', {
      'invoice_id': inv1,
      'menu_item_id': pepsi,
      'name': 'بيبسي',
      'category': 'drinks',
      'unit_price': 3000,
      'quantity': 3,
    });
    // فاتورة يوم تشرين الثاني: خارج التقرير.
    await insert('invoices', {
      'customer_name': 'ب',
      'day_id': novDay,
      'status': 'closed',
      'created_at': '2026-11-01T11:00:00.000',
      'closed_at': '2026-11-01T12:00:00.000',
      'play_total': 5000,
      'items_total': 0,
      'minimum_adjustment': 0,
      'rounding_delta': 0,
      'final_total': 5000,
    });
    // فاتورة مفتوحة: لا تُحسب.
    await insert('invoices', {
      'customer_name': 'ج',
      'day_id': octDay,
      'status': 'open',
      'created_at': '2026-10-06T11:00:00.000',
    });

    // ── المشتريات: تُحسب بتاريخ الدفع ──
    final purchase = await insert('purchase_invoices', {
      'purchased_at': '2026-09-28T10:00:00.000',
      'discount': 5000,
      'created_at': created,
    });
    await insert('stock_purchases', {
      'menu_item_id': pepsi,
      'purchased_at': '2026-09-28T10:00:00.000',
      'packs': 1,
      'pieces_per_pack': 10,
      'pack_price': 50000,
      'total_pieces': 10,
      'unit_cost': 5000,
      'total_cost': 50000,
      'created_at': created,
      'invoice_id': purchase,
    });
    for (final p in [
      ['2026-09-30T10:00:00.000', 10000],
      ['2026-10-10T10:00:00.000', 20000],
      ['2026-11-02T10:00:00.000', 5000],
    ]) {
      await insert('purchase_payments', {
        'invoice_id': purchase,
        'paid_at': p[0],
        'amount': p[1],
      });
    }

    // ── المصاريف ──
    await addExpense(ExpenseKind.maintenance, 7000, DateTime(2026, 10, 3));
    await addExpense(ExpenseKind.salaries, 30000, DateTime(2026, 10, 31));
    await addExpense(ExpenseKind.supplies, 2000, DateTime(2026, 10, 4));
    await addExpense(ExpenseKind.withdrawals, 4000, DateTime(2026, 10, 6),
        withdrawer: 'أبو خالد');
    await addExpense(ExpenseKind.withdrawals, 6000, DateTime(2026, 10, 7),
        withdrawer: 'أبو خالد');
    await addExpense(ExpenseKind.withdrawals, 3000, DateTime(2026, 10, 8),
        withdrawer: 'سامر');
    await addExpense(ExpenseKind.reserve, 5000, DateTime(2026, 10, 9));
    await addExpense(ExpenseKind.reserve, 2000, DateTime(2026, 9, 10));
    await addExpense(ExpenseKind.maintenance, 99999, DateTime(2026, 11, 2));
    // مصروف محذوف: لا يُحسب.
    await addExpense(ExpenseKind.supplies, 777, DateTime(2026, 10, 12));
    final rows = await db.raw.query('expenses', where: 'amount = 777');
    await expenses.delete(rows.single['id'] as int);

    // ── الجرد ──
    Future<void> count(int item, String date, int diff) => insert('stock_counts', {
          'menu_item_id': item,
          'count_date': date,
          'expected': 10,
          'counted': 10 + diff,
          'difference': diff,
          'counted_at': '${date}T20:00:00.000',
        });
    await count(pepsi, '2026-10-10', -2);
    await count(pepsi, '2026-10-20', -1);
    await count(chips, '2026-10-12', 4);
    await count(pepsi, '2026-11-03', -9); // خارج الشهر
  }

  test('الإيراد حسب يوم العمل وليس وقت الإغلاق، والمفتوحة مستثناة', () async {
    await seedOctober();
    final r = await repo.build(2026, 10);

    expect(r.invoiceCount, 1);
    expect(r.playRevenue, 20000);
    expect(r.barRevenue, 10000);
    expect(r.adjustments, 2000);
    expect(r.totalRevenue, 32000);
    expect(r.topItems.single.name, 'بيبسي');
    expect(r.topItems.single.quantity, 3);
    expect(r.topItems.single.revenue, 9000);
  });

  test('مشتريات البوفيه بتاريخ الدفع، والديون حتى نهاية الشهر', () async {
    await seedOctober();

    final oct = await repo.build(2026, 10);
    expect(oct.buffetPurchases, 20000);
    // قيمة الفاتورة 50000 − خصم 5000 = 45000، المدفوع حتى 31 تشرين الأول 30000.
    expect(oct.unpaidPurchases, 15000);

    final sep = await repo.build(2026, 9);
    expect(sep.buffetPurchases, 10000);
    expect(sep.unpaidPurchases, 35000);

    final nov = await repo.build(2026, 11);
    expect(nov.buffetPurchases, 5000);
    expect(nov.unpaidPurchases, 10000);
  });

  test('المصاريف والربح والصافي والاحتياطي التراكمي', () async {
    await seedOctober();
    final r = await repo.build(2026, 10);

    expect(r.maintenance, 7000);
    expect(r.salaries, 30000);
    expect(r.supplies, 2000); // المحذوف (777) غير محسوب
    expect(r.withdrawals, 13000);
    expect(r.reserve, 5000);

    expect(r.operatingExpenses, 20000 + 7000 + 30000 + 2000);
    expect(r.operatingProfit, 32000 - 59000);
    expect(r.netAfterDistributions, -27000 - 13000 - 5000);
    expect(r.reserveBalance, 7000); // 5000 (تشرين الأول) + 2000 (أيلول)
  });

  test('سحوبات كل شخص مرتّبة بالأكبر أولًا', () async {
    await seedOctober();
    final r = await repo.build(2026, 10);

    expect(r.withdrawers, hasLength(2));
    expect(r.withdrawers.first.name, 'أبو خالد');
    expect(r.withdrawers.first.count, 2);
    expect(r.withdrawers.first.amount, 10000);
    expect(r.withdrawers.last.name, 'سامر');
    expect(r.withdrawers.last.amount, 3000);
  });

  test('فروقات الجرد مجمّعة بالصنف وبقيمتها', () async {
    await seedOctober();
    final r = await repo.build(2026, 10);

    expect(r.stockDifferences, hasLength(2));
    final pepsi = r.stockDifferences.first; // الأكبر قيمة مطلقة
    expect(pepsi.name, 'بيبسي');
    expect(pepsi.difference, -3);
    expect(pepsi.value, -4500);
    final chips = r.stockDifferences.last;
    expect(chips.name, 'شيبس');
    expect(chips.difference, 4);
    expect(chips.value, 2000);
    expect(r.stockDifferenceValue, -2500);
  });

  test('شهر بلا أي نشاط تقريره فارغ، وأول شهر فيه نشاط', () async {
    expect(await repo.earliestMonth(), isNull);
    await seedOctober();

    final empty = await repo.build(2025, 1);
    expect(empty.isEmpty, isTrue);
    expect(empty.totalRevenue, 0);
    expect(empty.operatingProfit, 0);

    expect(await repo.earliestMonth(), DateTime(2026, 9, 1));
  });

  MonthlyReport bigReport() => MonthlyReport(
        year: 2026,
        month: 10,
        invoiceCount: 40,
        playRevenue: 1500000,
        barRevenue: 800000,
        adjustments: -2500,
        totalRevenue: 2297500,
        buffetPurchases: 400000,
        expenses: const {
          ExpenseKind.maintenance: 50000,
          ExpenseKind.salaries: 900000,
          ExpenseKind.supplies: 30000,
          ExpenseKind.withdrawals: 300000,
          ExpenseKind.reserve: 100000,
        },
        withdrawers: const [
          WithdrawerTotal('أبو خالد', 3, 200000),
          WithdrawerTotal('سامر', 1, 100000),
        ],
        unpaidPurchases: 150000,
        reserveBalance: 450000,
        topItems: [
          for (var i = 1; i <= 10; i++) ItemStat('صنف $i', 100 - i, i * 10000),
        ],
        // عدد كبير من الصفوف ليُجبر الجدول على صفحة ثانية.
        stockDifferences: [
          for (var i = 1; i <= 90; i++) StockDifference('صنف جرد $i', i.isEven ? -i : i, 1000),
        ],
      );

  test('الجدول الطويل يمتد على أكثر من صفحة', () async {
    final pages = await MonthlyReportPdfBuilder.renderPages(
      bigReport(),
      const AppSettings(loungeName: 'صالة الاختبار'),
      now: DateTime(2026, 11, 15, 16, 30),
    );

    expect(pages.length, greaterThanOrEqualTo(2));
    for (final png in pages) {
      // توقيع PNG: 89 50 4E 47
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('الـPDF يُبنى ويبدأ بترويسة PDF صحيحة', () async {
    final bytes = await MonthlyReportPdfBuilder.build(
      bigReport(),
      const AppSettings(loungeName: 'صالة الاختبار'),
      now: DateTime(2026, 11, 15, 16, 30),
    );

    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
