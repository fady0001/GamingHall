import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// تجزئة كلمات السر بخوارزمية PBKDF2-HMAC-SHA256 مع ملح عشوائي لكل كلمة.
/// لا تُخزَّن كلمة السر نفسها أبدًا، ولا يمكن استرجاعها من القيمة المخزنة.
///
/// الصيغة المخزَّنة: `pbkdf2-sha256$<iterations>$<salt-b64>$<hash-b64>`
class PasswordHasher {
  PasswordHasher._();

  static const int defaultIterations = 100000;
  static const int _saltLength = 16;
  static const String _scheme = 'pbkdf2-sha256';

  static Future<String> hash(
    String password, {
    int iterations = defaultIterations,
  }) async {
    final salt = _randomBytes(_saltLength);
    final passwordBytes = utf8.encode(password);
    final derived = await Isolate.run(
      () => pbkdf2Sha256(passwordBytes, salt, iterations),
    );
    return '$_scheme\$$iterations\$${base64.encode(salt)}\$${base64.encode(derived)}';
  }

  static Future<bool> verify(String password, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _scheme) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) return false;

    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64.decode(parts[2]);
      expected = base64.decode(parts[3]);
    } catch (_) {
      return false;
    }

    final passwordBytes = utf8.encode(password);
    final actual = await Isolate.run(
      () => pbkdf2Sha256(passwordBytes, salt, iterations),
    );
    return constantTimeEquals(actual, expected);
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

/// PBKDF2 بطول مخرجات 32 بايت (كتلة واحدة من HMAC-SHA256).
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  final firstInput = <int>[...salt, 0, 0, 0, 1];
  var u = Uint8List.fromList(hmac.convert(firstInput).bytes);
  final result = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = Uint8List.fromList(hmac.convert(u).bytes);
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return result;
}

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
