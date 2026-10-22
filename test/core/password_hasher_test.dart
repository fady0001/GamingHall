import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/security/password_hasher.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 يطابق متجه الاختبار المعروف (RFC 7914)', () {
    // password="passwd", salt="salt", c=1, dkLen=64 → أول 32 بايت.
    // القيمة من RFC 7914 §11 (PBKDF2-HMAC-SHA-256, c=1).
    final out = pbkdf2Sha256('passwd'.codeUnits, 'salt'.codeUnits, 1);
    final hex = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(hex, '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
  });

  test('تجزئة وتحقق: الصحيحة تنجح والخاطئة تفشل', () async {
    final stored = await PasswordHasher.hash('كلمة-سر-123');
    expect(stored.startsWith('pbkdf2-sha256\$'), isTrue);
    expect(stored.contains('كلمة'), isFalse);
    expect(await PasswordHasher.verify('كلمة-سر-123', stored), isTrue);
    expect(await PasswordHasher.verify('كلمة-سر-124', stored), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('الملح عشوائي: نفس الكلمة تعطي قيمتين مختلفتين', () async {
    final a = await PasswordHasher.hash('same', iterations: 1000);
    final b = await PasswordHasher.hash('same', iterations: 1000);
    expect(a, isNot(b));
    expect(await PasswordHasher.verify('same', a), isTrue);
    expect(await PasswordHasher.verify('same', b), isTrue);
  });

  test('قيمة مخزنة تالفة ترفض بدون استثناء', () async {
    expect(await PasswordHasher.verify('x', 'garbage'), isFalse);
    expect(await PasswordHasher.verify('x', 'pbkdf2-sha256\$abc\$!!\$!!'), isFalse);
  });

  test('رمز الاسترداد: شكل صحيح وتطبيع', () {
    final code = generateRecoveryCode();
    expect(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$').hasMatch(code), isTrue);
    expect(normalizeRecoveryCode(code.toLowerCase()), code.replaceAll('-', ''));
    expect(generateRecoveryCode(), isNot(code));
  });
}
