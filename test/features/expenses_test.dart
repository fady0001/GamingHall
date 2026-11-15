import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/domain/validation_exception.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/core/utils/month_names.dart';
import 'package:gaming_hall/features/expenses/data/expense_repository_impl.dart';
import 'package:gaming_hall/features/expenses/domain/entities/expense.dart';

/// اختبارات المصاريف وسجل التعديلات (SQLite حقيقية في الذاكرة).
void main() {
  late AppDatabase db;
  late ExpenseRepositoryImpl repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  ExpenseInput input({
    ExpenseKind kind = ExpenseKind.maintenance,
    int amount = 50000,
    String description = 'تصليح مكيف',
    DateTime? date,
    String? withdrawer,
  }) =>
      ExpenseInput(
        kind: kind,
        amount: Money(amount),
        description: description,
        date: date ?? today,
        withdrawer: withdrawer,
      );

  Future<List<Expense>> month(int y, int m) => repo.watchMonth(y, m).first;
  Future<List<ExpenseLogEntry>> log() => repo.watchLog().first;

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    repo = ExpenseRepositoryImpl(db);
    await db.raw.insert('manager_account', {
      'id': 1,
      'username': 'sami',
      'password_hash': 'x',
      'recovery_hash': 'x',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  });

  tearDown(() async => db.close());

  test('إضافة مصروف تظهر في شهرها فقط وتُسجَّل باسم المدير', () async {
    final id = await repo.add(input());

    final inMonth = await month(today.year, today.month);
    expect(inMonth, hasLength(1));
    expect(inMonth.first.id, id);
    expect(inMonth.first.amount, const Money(50000));
    expect(inMonth.first.kind, ExpenseKind.maintenance);

    final other = DateTime(today.year, today.month - 1);
    expect(await month(other.year, other.month), isEmpty);

    final entries = await log();
    expect(entries, hasLength(1));
    expect(entries.first.action, ExpenseLogAction.added);
    expect(entries.first.actor, 'sami');
    expect(entries.first.before, isNull);
    expect(entries.first.after!['amount'], 50000);
  });

  test('المسحوبات تتطلب اسم الساحب ويُحفظ اسمه', () async {
    await expectLater(
      repo.add(input(kind: ExpenseKind.withdrawals, description: '')),
      throwsA(isA<ValidationException>()
          .having((e) => e.message, 'message', ExpenseErrors.withdrawer)),
    );
    await expectLater(
      repo.add(input(
          kind: ExpenseKind.withdrawals, description: '', withdrawer: '   ')),
      throwsA(isA<ValidationException>()),
    );

    await repo.add(input(
      kind: ExpenseKind.withdrawals,
      description: '',
      withdrawer: ' أبو خالد ',
    ));
    final saved = (await month(today.year, today.month)).single;
    expect(saved.withdrawer, 'أبو خالد');
    expect(await repo.watchWithdrawerNames().first, ['أبو خالد']);
  });

  test('اسم الساحب لا يُحفظ لغير المسحوبات', () async {
    await repo.add(input(withdrawer: 'شخص'));
    final saved = (await month(today.year, today.month)).single;
    expect(saved.withdrawer, isNull);
  });

  test('الوصف إلزامي إلا للمسحوبات والاحتياطي', () async {
    await expectLater(
      repo.add(input(kind: ExpenseKind.salaries, description: '  ')),
      throwsA(isA<ValidationException>()),
    );
    await repo.add(input(kind: ExpenseKind.reserve, description: ''));
    expect(await month(today.year, today.month), hasLength(1));
  });

  test('المبلغ الصفري أو التاريخ المستقبلي مرفوضان', () async {
    await expectLater(repo.add(input(amount: 0)), throwsA(isA<ValidationException>()));
    await expectLater(
      repo.add(input(date: today.add(const Duration(days: 1)))),
      throwsA(isA<ValidationException>()),
    );
    expect(await log(), isEmpty);
  });

  test('التعديل يسجّل القيم قبل وبعد، وبدون تغيير لا يُسجَّل شيء', () async {
    final id = await repo.add(input());

    await repo.update(id, input()); // لا تغيير
    expect(await log(), hasLength(1));

    await repo.update(id, input(amount: 75000, description: 'تصليح مكيف وكابل'));
    final entries = await log();
    expect(entries, hasLength(2));
    final edit = entries.first;
    expect(edit.action, ExpenseLogAction.edited);
    expect(edit.before!['amount'], 50000);
    expect(edit.after!['amount'], 75000);
    expect(edit.before!['description'], 'تصليح مكيف');
    expect(edit.after!['description'], 'تصليح مكيف وكابل');

    final saved = (await month(today.year, today.month)).single;
    expect(saved.amount, const Money(75000));
  });

  test('الحذف منطقي: يختفي من الشهر ويبقى في السجل', () async {
    final id = await repo.add(input());
    await repo.delete(id);

    expect(await month(today.year, today.month), isEmpty);
    final entries = await log();
    expect(entries.first.action, ExpenseLogAction.deleted);
    expect(entries.first.before!['amount'], 50000);
    expect(entries.first.after, isNull);

    final raw = await db.raw.query('expenses');
    expect(raw, hasLength(1));
    expect(raw.first['is_deleted'], 1);

    await expectLater(repo.delete(id), throwsA(isA<ValidationException>()));
    await expectLater(repo.update(id, input()), throwsA(isA<ValidationException>()));
  });

  test('validate يعيد الرسالة دون رمي استثناء', () {
    expect(input().validate(), isNull);
    expect(input(amount: 0).validate(), ExpenseErrors.amount);
    expect(input(kind: ExpenseKind.salaries, description: ' ').validate(),
        ExpenseErrors.description);
    expect(
      input(kind: ExpenseKind.withdrawals, description: '').validate(),
      ExpenseErrors.withdrawer,
    );
    expect(
      input(kind: ExpenseKind.withdrawals, description: '', withdrawer: ' ')
          .validate(),
      ExpenseErrors.withdrawer,
    );
    expect(
      input(kind: ExpenseKind.withdrawals, description: '', withdrawer: 'سامر')
          .validate(),
      isNull,
    );
    expect(input(date: today.add(const Duration(days: 1))).validate(),
        ExpenseErrors.futureDate);
  });

  test('sanitized ينظّف الفراغات ويحذف الساحب لغير المسحوبات', () {
    final w = input(
      kind: ExpenseKind.withdrawals,
      description: '  ',
      withdrawer: ' أبو خالد ',
    ).sanitized();
    expect(w.withdrawer, 'أبو خالد');
    expect(w.description, '');
    expect(input(withdrawer: 'شخص').sanitized().withdrawer, isNull);
  });

  test('أسماء الأشهر بالشامي', () {
    expect(shamiMonthName(1), 'كانون الثاني');
    expect(shamiMonthName(2), 'شباط');
    expect(shamiMonthName(12), 'كانون الأول');
    expect(monthLabel(2026, 11), 'تشرين الثاني 2026');
  });
}
