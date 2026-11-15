import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/database/db_utils.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/features/expenses/data/expense_repository_impl.dart';
import 'package:gaming_hall/features/expenses/domain/entities/expense.dart';
import 'package:gaming_hall/features/expenses/presentation/cubit/expenses_cubit.dart';

/// مشتريات البوفيه في صفحة المصاريف: عرض فقط، حسب تاريخ الدفع، وتُحسب
/// مع إجمالي الشهر.
void main() {
  late AppDatabase db;
  late ExpenseRepositoryImpl repo;

  Future<int> invoice(DateTime purchasedAt, {String? supplier, String? no}) =>
      db.raw.insert('purchase_invoices', {
        'purchased_at': dbTime(purchasedAt),
        'supplier': supplier,
        'invoice_no': no,
        'discount': 0,
        'created_at': dbTime(purchasedAt),
      });

  Future<void> pay(int invoiceId, int amount, DateTime at) =>
      db.raw.insert('purchase_payments', {
        'invoice_id': invoiceId,
        'amount': amount,
        'paid_at': dbTime(at),
      });

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    repo = ExpenseRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  test('الدفعات تُعرض حسب شهر الدفع (لا شهر الفاتورة) من الأحدث', () async {
    // فاتورة آخر تشرين الأول سُدِّدت دفعة منها في تشرين الأول وأخرى في الثاني.
    final a = await invoice(DateTime(2026, 10, 30, 12),
        supplier: 'أبو سعيد', no: 'A-17');
    await pay(a, 20000, DateTime(2026, 10, 30, 12));
    await pay(a, 5000, DateTime(2026, 11, 2, 9));
    final b = await invoice(DateTime(2026, 11, 5, 10));
    await pay(b, 7000, DateTime(2026, 11, 5, 10));

    final nov = await repo.watchBuffetPayments(2026, 11).first;
    expect(nov.map((p) => p.amount.amount), [7000, 5000]);
    expect(nov.last.supplier, 'أبو سعيد');
    expect(nov.last.invoiceNo, 'A-17');
    expect(nov.last.purchasedAt, DateTime(2026, 10, 30, 12));
    expect(nov.first.supplier, isNull);

    final oct = await repo.watchBuffetPayments(2026, 10).first;
    expect(oct.map((p) => p.amount.amount), [20000]);

    expect(await repo.watchBuffetPayments(2026, 9).first, isEmpty);
  });

  test('غير المسدَّد يُحسب حتى نهاية الشهر المعروض فقط', () async {
    // فاتورة بتاريخ 10 تشرين الثاني قيمتها 50000 (سطر واحد) دُفع منها 20000.
    final a = await invoice(DateTime(2026, 11, 10, 10));
    await db.raw.insert('stock_purchases', {
      'menu_item_id': 1,
      'purchased_at': dbTime(DateTime(2026, 11, 10, 10)),
      'packs': 1,
      'pieces_per_pack': 1,
      'pack_price': 50000,
      'total_pieces': 1,
      'unit_cost': 50000,
      'total_cost': 50000,
      'created_at': dbTime(DateTime(2026, 11, 10, 10)),
      'invoice_id': a,
      'entry_mode': 'pack',
    });
    await pay(a, 20000, DateTime(2026, 11, 10, 10));
    // دفعة لاحقة في كانون الأول تُسدّد 10000 أخرى.
    await pay(a, 10000, DateTime(2026, 12, 3, 9));

    expect((await repo.watchBuffetUnpaid(2026, 11).first).amount, 30000);
    expect((await repo.watchBuffetUnpaid(2026, 12).first).amount, 20000);
    // قبل تاريخ الفاتورة لا شيء.
    expect((await repo.watchBuffetUnpaid(2026, 10).first).amount, 0);
  });

  test('إجمالي الشهر يجمع المصاريف مع مشتريات البوفيه', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await repo.add(ExpenseInput(
      kind: ExpenseKind.maintenance,
      amount: const Money(3000),
      description: 'تصليح',
      date: today,
    ));
    final inv = await invoice(now, supplier: 'مورّد');
    await pay(inv, 12000, now);

    final cubit = ExpensesCubit(repo);
    addTearDown(cubit.close);
    final state = await cubit.stream
        .firstWhere((s) => !s.isLoading)
        .timeout(const Duration(seconds: 5));

    expect(state.buffetTotal, const Money(12000));
    expect(state.totalFor(ExpenseKind.maintenance), const Money(3000));
    expect(state.total, const Money(15000));
  });
}
