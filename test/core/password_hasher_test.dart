import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/security/password_hasher.dart';
import 'package:gaming_hall/core/security/pbkdf2_engine.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256 (تنفيذ Dart)', () {
    test('يطابق متجه الاختبار المعروف (RFC 7914)', () {
      // password="passwd", salt="salt", c=1 → أول 32 بايت.
      final out = pbkdf2Sha256('passwd'.codeUnits, 'salt'.codeUnits, 1);
      expect(_hex(out),
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
    });

    test('متجه 4096 تكرارًا', () {
      final out = pbkdf2Sha256('password'.codeUnits, 'salt'.codeUnits, 4096);
      expect(_hex(out),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('مفاتيح بأطوال حدّية (فارغ، 64، 65، 100 بايت) تطابق Python', () {
      expect(
        _hex(pbkdf2Sha256(List.filled(100, 0x70), 'salt-long'.codeUnits, 1000)),
        '9c8e9040de6a816a4e57d1ec6e10df29b19feeae5fafdc3ce4ed5cc2331ba79c',
      );
      expect(
        _hex(pbkdf2Sha256(List.filled(64, 0x70), 'S'.codeUnits, 7)),
        '5aa5d2739b551bde4b73f177be72783c1ac202d3b43c383c4d0e9af248f5fa7a',
      );
      expect(
        _hex(pbkdf2Sha256(List.filled(65, 0x70), List.filled(70, 0x53), 7)),
        'e32980ca9b710f19ccda53f3ec09fa5f7ecd63b61ca88940f202c19c2b72ffb2',
      );
      expect(
        _hex(pbkdf2Sha256(<int>[], 'S'.codeUnits, 3)),
        '18e1d8b569faaa89d6120cb86d67119d12d1b567ba19cae41ce03f04410f5f2c',
      );
    });

    test('كلمة سر عربية بـ 100,000 تكرار تطابق Python', () {
      final out = pbkdf2Sha256(
        utf8.encode('كلمة-سر-123'),
        utf8.encode('0123456789abcdef'),
        100000,
      );
      expect(_hex(out),
          '7bdfa4bf189dd427c45dfc2b33e4cc9b9479167ceacb709036a9f4e690107626');
    });
  });

  group('المحرّك (الأصلي إن توفر، وإلا Dart)', () {
    test('ناتجه مطابق دائمًا لتنفيذ Dart — يفحص مسار ويندوز الأصلي أيضًا', () {
      final random = Random(42);
      for (var i = 0; i < 12; i++) {
        final password =
            List<int>.generate(1 + random.nextInt(90), (_) => random.nextInt(256));
        final salt =
            List<int>.generate(1 + random.nextInt(40), (_) => random.nextInt(256));
        final iterations = 1 + random.nextInt(3000);
        final viaEngine = Pbkdf2Engine.derive(password, salt, iterations).bytes;
        final viaDart = pbkdf2Sha256Dart(password, salt, iterations);
        expect(_hex(viaEngine), _hex(viaDart),
            reason: 'طول كلمة السر ${password.length}، تكرارات $iterations');
      }
    });
  });

  group('PasswordHasher', () {
    test('تجزئة وتحقق: الصحيحة تنجح والخاطئة تفشل', () async {
      final stored = await PasswordHasher.hash('كلمة-سر-123');
      expect(stored.startsWith('pbkdf2-sha256\$'), isTrue);
      expect(stored.contains('كلمة'), isFalse);
      expect(await PasswordHasher.verify('كلمة-سر-123', stored), isTrue);
      expect(await PasswordHasher.verify('كلمة-سر-124', stored), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('التجزئات الجديدة أقوى من القديمة (≥ 300,000 تكرار) ولا تحتاج ترقية',
        () async {
      final stored = await PasswordHasher.hash('secret-1');
      final iterations = int.parse(stored.split(r'$')[1]);
      expect(iterations, greaterThanOrEqualTo(PasswordHasher.fallbackIterations));
      final check = await PasswordHasher.verifyAndCheck('secret-1', stored);
      expect(check.valid, isTrue);
      expect(check.needsRehash, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('تجزئة قديمة (100,000 تكرار) تبقى صالحة وتُعلَّم للترقية', () async {
      // مولَّدة بـ Python: hashlib.pbkdf2_hmac('sha256', 'كلمة-سر-123', salt, 100000)
      const legacy = r'pbkdf2-sha256$100000$MDEyMzQ1Njc4OWFiY2RlZg==$'
          r'e9+kvxid1CfEXfwrM+TMm5R5Fnzqy3CQNqn05pAQdiY=';
      final good = await PasswordHasher.verifyAndCheck('كلمة-سر-123', legacy);
      expect(good.valid, isTrue);
      expect(good.needsRehash, isTrue);

      final bad = await PasswordHasher.verifyAndCheck('كلمة-سر-124', legacy);
      expect(bad.valid, isFalse);
      expect(bad.needsRehash, isFalse); // لا ترقية بعد فشل التحقق
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('الملح عشوائي: نفس الكلمة تعطي قيمتين مختلفتين', () async {
      final a = await PasswordHasher.hash('same', iterations: 1000);
      final b = await PasswordHasher.hash('same', iterations: 1000);
      expect(a, isNot(b));
      expect(await PasswordHasher.verify('same', a), isTrue);
      expect(await PasswordHasher.verify('same', b), isTrue);
    });

    test('قيمة مخزنة تالفة أو مُعبَث بها ترفض بدون استثناء وبسرعة', () async {
      expect(await PasswordHasher.verify('x', 'garbage'), isFalse);
      expect(await PasswordHasher.verify('x', 'pbkdf2-sha256\$abc\$!!\$!!'), isFalse);
      // عدد تكرارات خرافي لا يجمّد التطبيق.
      expect(
        await PasswordHasher.verify('x', 'pbkdf2-sha256\$2000000000\$AAAAAAAAAAAAAAAAAAAAAA==\$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='),
        isFalse,
      );
      // تجزئة بطول خاطئ.
      expect(
        await PasswordHasher.verify('x', 'pbkdf2-sha256\$1000\$AAAAAAAAAAAAAAAAAAAAAA==\$AAAA'),
        isFalse,
      );
      // صفر تكرارات.
      expect(
        await PasswordHasher.verify('x', 'pbkdf2-sha256\$0\$AAAAAAAAAAAAAAAAAAAAAA==\$AAAA'),
        isFalse,
      );
    });

    test('رمز الاسترداد: شكل صحيح وتطبيع', () {
      final code = generateRecoveryCode();
      expect(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$').hasMatch(code), isTrue);
      expect(normalizeRecoveryCode(code.toLowerCase()), code.replaceAll('-', ''));
      expect(generateRecoveryCode(), isNot(code));
    });
  });
}
