import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/security/password_hasher.dart';
import 'package:gaming_hall/features/auth/data/auth_repository_impl.dart';

/// اختبارات تكامل أمان الدخول على قاعدة SQLite حقيقية في الذاكرة.
void main() {
  late AppDatabase db;
  late AuthRepositoryImpl auth;

  setUp(() async {
    db = await AppDatabase.open(path: ':memory:');
    auth = AuthRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<String> readHash() async =>
      ((await db.raw.query('manager_account')).single['password_hash']) as String;

  test('المحاولات المتوازية لا تتجاوز حدّ المحاولات قبل القفل', () async {
    await auth.createManagerAccount(username: 'admin', password: 'secret1');

    // 20 محاولة تُطلق في اللحظة نفسها (هجوم تخمين متوازٍ).
    final outcomes = await Future.wait([
      for (var i = 0; i < 20; i++) auth.login(username: 'admin', password: 'wrong$i'),
    ]);

    expect(outcomes.every((o) => !o.success), isTrue);
    // لم يُفحص إلا 5 تخمينات فقط، والباقي رُفض بسبب القفل دون أي فحص.
    final failed = await db.raw
        .query('settings', where: 'key = ?', whereArgs: ['auth_failed_count']);
    expect(failed.single['value'], '5');

    // وحتى كلمة السر الصحيحة مرفوضة أثناء القفل.
    final correct = await auth.login(username: 'admin', password: 'secret1');
    expect(correct.success, isFalse);
    expect(correct.isLocked, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('الدخول الناجح لا يترك عدّادات فشل ولا يعيد كتابة القاعدة بلا داعٍ', () async {
    await auth.createManagerAccount(username: 'admin', password: 'secret1');
    await auth.login(username: 'admin', password: 'bad-1');
    await auth.login(username: 'admin', password: 'bad-2');
    expect((await auth.login(username: 'admin', password: 'secret1')).success, isTrue);

    final left = await db.raw.query('settings',
        where: 'key IN (?, ?)', whereArgs: ['auth_failed_count', 'auth_locked_until']);
    expect(left, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('تجزئة قديمة (100,000 تكرار) تقبل الدخول ثم تُرقّى تلقائيًا', () async {
    await auth.createManagerAccount(username: 'admin', password: 'secret1');
    final legacy = await PasswordHasher.hash('secret1', iterations: 100000);
    await db.raw.update('manager_account', {'password_hash': legacy});

    expect((await auth.login(username: 'admin', password: 'secret1')).success, isTrue);

    // الترقية تتم في الخلفية؛ ننتظرها بحدّ أقصى.
    var upgraded = false;
    for (var i = 0; i < 100 && !upgraded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final iterations = int.parse((await readHash()).split(r'$')[1]);
      upgraded = iterations > 100000;
    }
    expect(upgraded, isTrue);

    // كلمة السر نفسها تعمل بعد الترقية، والخاطئة ما زالت مرفوضة.
    expect((await auth.login(username: 'admin', password: 'secret1')).success, isTrue);
    expect((await auth.login(username: 'admin', password: 'nope-nope')).success, isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
