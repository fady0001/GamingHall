import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'pbkdf2_engine.dart';

/// تجزئة كلمات السر بخوارزمية PBKDF2-HMAC-SHA256 مع ملح عشوائي لكل كلمة.
/// لا تُخزَّن كلمة السر نفسها أبدًا، ولا يمكن استرجاعها من القيمة المخزنة.
///
/// الصيغة المخزَّنة (لم تتغير، فالتجزئات القديمة تبقى صالحة):
/// `pbkdf2-sha256$<iterations>$<salt-b64>$<hash-b64>`
///
/// الأداء والأمان:
///  * الحساب يتم في Isolate منفصل فلا تتجمّد الواجهة.
///  * على ويندوز يُستخدم محرّك النظام الأصلي (CNG) فيكون الحساب بأجزاء من
///    الثانية، وهذا يسمح برفع عدد التكرارات إلى 600,000 (توصية OWASP الحالية
///    لهذه الخوارزمية) بدل 100,000 دون أي بطء ملحوظ.
///  * إن تعذّر المحرّك الأصلي يُستخدم تنفيذ Dart محسَّن بنفس الناتج تمامًا
///    وبعدد تكرارات 300,000 (ما زال ثلاثة أضعاف القيمة القديمة).
///  * التجزئات القديمة (100,000 تكرار) تُقبل كما هي وتُرقّى تلقائيًا إلى
///    العدد الأقوى عند أول دخول ناجح (انظر [verifyAndCheck]).
class PasswordHasher {
  PasswordHasher._();

  /// عدد التكرارات للتجزئات الجديدة عند توفر المحرّك الأصلي.
  static const int nativeIterations = 600000;

  /// عدد التكرارات للتجزئات الجديدة إن لم يتوفر المحرّك الأصلي.
  static const int fallbackIterations = 300000;

  /// سقف أمان عند التحقق: قيمة مخزنة مُعبَث بها (ملايين التكرارات) لا يجوز أن
  /// تُجمّد التطبيق. أكبر من ضعف أعلى قيمة نكتبها نحن.
  static const int maxAcceptedIterations = 2000000;

  static const int _saltLength = 16;
  static const int _hashLength = 32;
  static const String _scheme = 'pbkdf2-sha256';

  /// يُنشئ تجزئة جديدة. [iterations] للاختبارات فقط؛ في الإنتاج يُترك فارغًا
  /// ليُختار أقوى عدد مناسب لهذا الجهاز.
  static Future<String> hash(String password, {int? iterations}) async {
    final salt = _randomBytes(_saltLength);
    final passwordBytes = utf8.encode(password);
    return Isolate.run(() => _hashTask(passwordBytes, salt, iterations));
  }

  static Future<bool> verify(String password, String stored) async =>
      (await verifyAndCheck(password, stored)).valid;

  /// يتحقق من كلمة السر، ويخبر أيضًا إن كانت التجزئة المخزنة أضعف من المستوى
  /// الحالي ويجدر إعادة تجزئتها (يُنفَّذ ذلك فقط بعد نجاح التحقق).
  static Future<PasswordCheck> verifyAndCheck(
    String password,
    String stored,
  ) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return PasswordCheck.invalid;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null ||
        iterations < 1 ||
        iterations > maxAcceptedIterations) {
      return PasswordCheck.invalid;
    }

    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64.decode(parts[2]);
      expected = base64.decode(parts[3]);
    } catch (_) {
      return PasswordCheck.invalid;
    }
    if (salt.isEmpty || expected.length != _hashLength) {
      return PasswordCheck.invalid;
    }

    final passwordBytes = utf8.encode(password);
    final result = await Isolate.run(
      () => _verifyTask(passwordBytes, salt, expected, iterations),
    );
    return PasswordCheck(valid: result[0], needsRehash: result[1]);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// نتيجة [PasswordHasher.verifyAndCheck].
class PasswordCheck {
  final bool valid;

  /// صحيح فقط إن كانت كلمة السر صحيحة والتجزئة المخزنة أضعف من الحالية.
  final bool needsRehash;

  const PasswordCheck({required this.valid, required this.needsRehash});

  static const PasswordCheck invalid =
      PasswordCheck(valid: false, needsRehash: false);
}

int _targetIterations(bool nativeAvailable) => nativeAvailable
    ? PasswordHasher.nativeIterations
    : PasswordHasher.fallbackIterations;

// تعمل داخل Isolate منفصل.
String _hashTask(Uint8List password, Uint8List salt, int? iterations) {
  final count = iterations ?? _targetIterations(Pbkdf2Engine.nativeAvailable);
  final derived = Pbkdf2Engine.derive(password, salt, count).bytes;
  return 'pbkdf2-sha256\$$count\$${base64.encode(salt)}\$${base64.encode(derived)}';
}

// تعمل داخل Isolate منفصل. تعيد [valid, needsRehash].
List<bool> _verifyTask(
  Uint8List password,
  Uint8List salt,
  Uint8List expected,
  int iterations,
) {
  final result = Pbkdf2Engine.derive(password, salt, iterations);
  final valid = constantTimeEquals(result.bytes, expected);
  final needsRehash = valid && iterations < _targetIterations(result.usedNative);
  return [valid, needsRehash];
}

/// PBKDF2 بطول مخرجات 32 بايت (كتلة واحدة من HMAC-SHA256). متزامنة وثقيلة:
/// للاختبارات والاستخدام داخل Isolate فقط.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) =>
    pbkdf2Sha256Dart(password, salt, iterations);

/// مقارنة بزمن ثابت (لا تتوقف عند أول اختلاف).
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// رمز استرداد حساب المدير: 16 حرفًا بدون أحرف ملتبسة (0/O و1/I)، بصيغة
/// XXXX-XXXX-XXXX-XXXX.
String generateRecoveryCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  final chars = List<String>.generate(
    16,
    (_) => alphabet[random.nextInt(alphabet.length)],
  );
  final groups = <String>[];
  for (var i = 0; i < 16; i += 4) {
    groups.add(chars.sublist(i, i + 4).join());
  }
  return groups.join('-');
}

/// يوحّد شكل رمز الاسترداد المُدخَل (أحرف كبيرة بدون شرطات/مسافات).
String normalizeRecoveryCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
