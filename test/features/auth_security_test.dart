import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/database/app_database.dart';
import 'package:gaming_hall/core/security/password_hasher.dart';
import 'package:gaming_hall/core/security/reset_authorization.dart';
import 'package:gaming_hall/features/auth/data/auth_repository_impl.dart';
import 'package:gaming_hall/features/auth/domain/repositories/auth_repository.dart';

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

  group('فقد رمز الاسترداد: رمز جديد من الإعدادات ثم تفويض الدعم الفني', () {
    const deviceCode = 'AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDD';
    late List<int> seed;
    late SimplePublicKey publicKey;
    late DateTime now;
    late String device;
    late AuthRepositoryImpl secured;

    setUp(() async {
      final keyPair = await Ed25519().newKeyPair();
      seed = await keyPair.extractPrivateKeyBytes();
      publicKey = await keyPair.extractPublicKey();
      now = DateTime.utc(2026, 11, 17, 12);
      device = deviceCode;
      secured = AuthRepositoryImpl(
        db,
        fingerprint: () async => device,
        authorityKey: publicKey,
        clock: () => now,
      );
    });

    // ما يفعله المطوّر بأداة tool/license_tool.dart reset.
    Future<String> support(String requestCode) => ResetAuthorization.issue(
          request: ResetRequest.tryParse(requestCode)!,
          privateKeySeed: seed,
          now: now,
        );

    Matcher authError([String? part]) => throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            part == null ? isNotEmpty : contains(part),
          ),
        );

    test('إنشاء رمز استرداد جديد يطلب كلمة السر ويُبطل الرمز القديم', () async {
      final oldCode =
          await secured.createManagerAccount(username: 'admin', password: 'secret1');

      await expectLater(
          secured.regenerateRecoveryCode(currentPassword: 'wrong'), authError());

      final newCode =
          await secured.regenerateRecoveryCode(currentPassword: 'secret1');
      expect(newCode, isNot(oldCode));
      await expectLater(
        secured.resetWithRecoveryCode(recoveryCode: oldCode, newPassword: 'abcdef'),
        authError(),
      );
      await secured.resetWithRecoveryCode(recoveryCode: newCode, newPassword: 'abcdef');
      expect((await secured.login(username: 'admin', password: 'abcdef')).success, isTrue);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('رمز الطلب فيه مجموع تحقق يكشف خطأ النسخ', () {
      final text = ResetRequest(
        fingerprint: deviceCode,
        nonce: ResetRequest.generateNonce(),
        issuedAt: 1790000000,
      ).encode();
      expect(ResetRequest.tryParse(text), isNotNull);
      expect(ResetRequest.tryParse(text.toLowerCase()), isNotNull);

      // تغيير حرف واحد في كود الجهاز أو في الـ nonce يُرفض.
      final index = text.indexOf('AAAAAAAA') + 2;
      final tampered = text.replaceRange(index, index + 1, 'B');
      expect(ResetRequest.tryParse(tampered), isNull);
      // نص مقصوص أو بلا مجموع تحقق يُرفض.
      expect(ResetRequest.tryParse(text.substring(0, text.length - 5)), isNull);
    });

    test('رمز الطلب يُعاد نفسه ما دام معلّقًا، و"طلب جديد" يستبدله', () async {
      await secured.createManagerAccount(username: 'admin', password: 'secret1');
      final first = await secured.createResetRequest();
      expect(ResetRequest.tryParse(first)?.fingerprint, deviceCode);
      expect(await secured.createResetRequest(), first);
      expect(await secured.createResetRequest(forceNew: true), isNot(first));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('التفويض الصحيح يعيّن كلمة سر جديدة ورمز استرداد جديدًا لمرة واحدة',
        () async {
      final oldCode =
          await secured.createManagerAccount(username: 'admin', password: 'secret1');
      final request = await secured.createResetRequest();
      now = now.add(const Duration(hours: 2));
      final token = await support(request);

      final newCode = await secured.resetWithAuthorization(
          authorizationCode: token, newPassword: 'brandnew1');
      expect(newCode, isNot(oldCode));
      expect((await secured.login(username: 'admin', password: 'brandnew1')).success, isTrue);
      expect((await secured.login(username: 'admin', password: 'secret1')).success, isFalse);

      // إعادة استخدام الرمز نفسه مرفوضة.
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: token, newPassword: 'hacker12'),
        authError('لا يوجد طلب'),
      );
      expect((await secured.login(username: 'admin', password: 'brandnew1')).success, isTrue);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('يُرفض: جهاز مختلف، منتهي الصلاحية، ساعة مرجَّعة، رمز تالف', () async {
      await secured.createManagerAccount(username: 'admin', password: 'secret1');
      final request = await secured.createResetRequest();
      final token = await support(request);

      // رمز صادر لجهاز آخر.
      final parsed = ResetRequest.tryParse(request)!;
      final otherDevice = ResetRequest(
        fingerprint: 'AAAAAAAA-BBBBBBBB-CCCCCCCC-DDDDDDDE',
        nonce: parsed.nonce,
        issuedAt: parsed.issuedAt,
      ).encode();
      await expectLater(
        secured.resetWithAuthorization(
            authorizationCode: await support(otherDevice), newPassword: 'abcdef'),
        authError('غير صالح'),
      );

      // الطلب أُنشئ على جهاز آخر (نُقلت القاعدة).
      device = 'EEEEEEEE-BBBBBBBB-CCCCCCCC-DDDDDDDD';
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: token, newPassword: 'abcdef'),
        authError('جهاز مختلف'),
      );
      device = deviceCode;

      // رمز مقصوص.
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: 'A1.12', newPassword: 'abcdef'),
        authError('غير مكتمل'),
      );

      // ساعة الجهاز رُجِّعت قبل وقت الطلب.
      now = DateTime.utc(2026, 11, 14, 12);
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: token, newPassword: 'abcdef'),
        authError('تاريخ الجهاز'),
      );

      // بعد 25 ساعة.
      now = DateTime.utc(2026, 11, 18, 13);
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: token, newPassword: 'abcdef'),
        authError('انتهت'),
      );

      // كلمة السر لم تتغير بعد كل هذه المحاولات.
      now = DateTime.utc(2026, 11, 17, 12);
      expect((await secured.login(username: 'admin', password: 'secret1')).success, isTrue);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('الاسترداد برمز الاسترداد يُلغي الطلب المعلّق، وتزوير الرمز يقفل', () async {
      final code =
          await secured.createManagerAccount(username: 'admin', password: 'secret1');
      final request = await secured.createResetRequest();
      final token = await support(request);

      await secured.resetWithRecoveryCode(recoveryCode: code, newPassword: 'abcdef');
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: token, newPassword: 'zzzzzz'),
        authError('لا يوجد طلب'),
      );

      final request2 = await secured.createResetRequest();
      final good = await support(request2);
      final forged = '${good.substring(0, good.length - 4)}AAAA';
      for (var i = 0; i < 5; i++) {
        await expectLater(
          secured.resetWithAuthorization(authorizationCode: forged, newPassword: 'abcdef'),
          authError(),
        );
      }
      await expectLater(
        secured.resetWithAuthorization(authorizationCode: good, newPassword: 'abcdef'),
        authError('محاولات كثيرة'),
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
