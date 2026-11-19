import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// طلب إعادة التعيين الذي يولّده التطبيق عندما يفقد المدير كلمة السر ورمز
/// الاسترداد معًا. يرسله المدير للمطوّر، فيردّ بـ [ResetAuthorization].
///
/// الصيغة: `R1-<كود الجهاز 32 خانة hex>-<nonce 16 حرفًا>-<وقت الطلب بالثواني>-<مجموع تحقق 4 خانات hex>`
/// مجموع التحقق يكشف أي خطأ في النسخ أو الكتابة قبل أن يوقّع المطوّر الطلب.
///
/// هذا الملف Dart نقي (بدون Flutter) ليستخدمه التطبيق و`tool/license_tool.dart`
/// بنفس الكود، فلا يمكن أن تختلف صيغة الرسالة الموقَّعة بين الطرفين.
class ResetRequest {
  final String fingerprint; // XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX
  final String nonce;
  final int issuedAt; // ثوانٍ منذ 1970 (UTC)

  const ResetRequest({
    required this.fingerprint,
    required this.nonce,
    required this.issuedAt,
  });

  static const String nonceAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int nonceLength = 16;

  /// أقصى عمر لطلب معلّق: بعده يُنشأ طلب جديد، ويرفض المطوّر توقيعه.
  static const Duration maxAge = Duration(days: 7);

  /// يوحّد كود الجهاز إلى `XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX`. null إن لم
  /// يكن 32 خانة hex.
  static String? canonicalFingerprint(String raw) {
    final hex = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (hex.length != 32) return null;
    return [
      hex.substring(0, 8),
      hex.substring(8, 16),
      hex.substring(16, 24),
      hex.substring(24, 32),
    ].join('-');
  }

  static String generateNonce([Random? random]) {
    final r = random ?? Random.secure();
    return List<String>.generate(
      nonceLength,
      (_) => nonceAlphabet[r.nextInt(nonceAlphabet.length)],
    ).join();
  }

  /// مجموع تحقق CRC-16 (CCITT) بأربع خانات hex كبيرة، يُحسب على نص الطلب.
  static String _checksum(String body) {
    var crc = 0xFFFF;
    for (final byte in utf8.encode(body)) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  String encode() {
    final body = '${fingerprint.replaceAll('-', '')}-$nonce-$issuedAt';
    return 'R1-$body-${_checksum(body)}';
  }

  /// يقرأ طلبًا نُسخ من واتساب أو من الشاشة (يتجاهل المسافات وحالة الأحرف).
  /// null إن كان تالفًا.
  static ResetRequest? tryParse(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final parts = text.split('-');
    if (parts.length != 5 || parts[0] != 'R1') return null;
    // أي خطأ نسخ أو كتابة في الحقول الثلاثة يُكتشف هنا.
    if (_checksum('${parts[1]}-${parts[2]}-${parts[3]}') != parts[4]) return null;
    final fingerprint = canonicalFingerprint(parts[1]);
    if (fingerprint == null || parts[1].length != 32) return null;
    if (!RegExp('^[$nonceAlphabet]{$nonceLength}\$').hasMatch(parts[2])) {
      return null;
    }
    final issuedAt = int.tryParse(parts[3]);
    if (issuedAt == null || issuedAt <= 0) return null;
    return ResetRequest(
      fingerprint: fingerprint,
      nonce: parts[2],
      issuedAt: issuedAt,
    );
  }
}

enum ResetAuthorizationStatus {
  valid,
  malformed,
  badSignature,
  expired,
  clockInvalid,
}

/// رمز التفويض الذي يوقّعه المطوّر بمفتاحه الخاص (Ed25519) لطلب محدد.
///
/// الصيغة: `A1.<وقت الانتهاء بالثواني>.<التوقيع Base64Url>`
/// الرسالة الموقَّعة: `GL1R:<كود الجهاز>:<nonce>:<وقت الطلب>:<وقت الانتهاء>`
///
/// لذلك الرمز لا يصلح إلا لهذا الجهاز ولهذا الطلب بعينه، ولا يصلح بعد انتهاء
/// مدته، ولا يمكن تعديل أي حقل فيه دون إبطال التوقيع.
class ResetAuthorization {
  ResetAuthorization._();

  /// مدة صلاحية الرمز بعد إصداره.
  static const Duration validity = Duration(hours: 24);

  /// سماح بفارق ساعة الجهاز (بالثواني).
  static const int clockSkewSeconds = 5 * 60;

  static String signedMessage({
    required String fingerprint,
    required String nonce,
    required int issuedAt,
    required int expiresAt,
  }) =>
      'GL1R:$fingerprint:$nonce:$issuedAt:$expiresAt';

  static int _seconds(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;

  /// للمطوّر فقط (يُستدعى من tool/license_tool.dart): يوقّع [request].
  static Future<String> issue({
    required ResetRequest request,
    required List<int> privateKeySeed,
    DateTime? now,
  }) async {
    final nowSeconds = _seconds(now ?? DateTime.now());
    final expiresAt = nowSeconds + validity.inSeconds;
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKeySeed);
    final signature = await algorithm.sign(
      utf8.encode(signedMessage(
        fingerprint: request.fingerprint,
        nonce: request.nonce,
        issuedAt: request.issuedAt,
        expiresAt: expiresAt,
      )),
      keyPair: keyPair,
    );
    final sig = base64Url.encode(signature.bytes).replaceAll('=', '');
    return 'A1.$expiresAt.$sig';
  }

  /// يتحقق من [token] مقابل الطلب المعلّق المخزَّن في التطبيق وكود هذا الجهاز.
  static Future<ResetAuthorizationStatus> verify({
    required String token,
    required String fingerprint,
    required String nonce,
    required int issuedAt,
    required SimplePublicKey publicKey,
    required DateTime now,
  }) async {
    final parts = token.replaceAll(RegExp(r'\s+'), '').split('.');
    if (parts.length != 3 || parts[0] != 'A1') {
      return ResetAuthorizationStatus.malformed;
    }
    final expiresAt = int.tryParse(parts[1]);
    if (expiresAt == null || expiresAt <= 0) {
      return ResetAuthorizationStatus.malformed;
    }
    final List<int> signatureBytes;
    try {
      signatureBytes = base64Url.decode(base64Url.normalize(parts[2]));
    } catch (_) {
      return ResetAuthorizationStatus.malformed;
    }
    if (signatureBytes.length != 64) return ResetAuthorizationStatus.malformed;

    final bool authentic;
    try {
      authentic = await Ed25519().verify(
        utf8.encode(signedMessage(
          fingerprint: fingerprint,
          nonce: nonce,
          issuedAt: issuedAt,
          expiresAt: expiresAt,
        )),
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
    } catch (_) {
      return ResetAuthorizationStatus.badSignature;
    }
    if (!authentic) return ResetAuthorizationStatus.badSignature;

    final nowSeconds = _seconds(now);
    // ساعة الجهاز رُجِّعت إلى ما قبل الطلب نفسه: لا نثق بها.
    if (nowSeconds < issuedAt - clockSkewSeconds) {
      return ResetAuthorizationStatus.clockInvalid;
    }
    // سقف أمان: حتى لو وُقّع رمز بمدة أطول، لا نقبل أكثر من عمر الطلب + المدة.
    final hardLimit =
        issuedAt + ResetRequest.maxAge.inSeconds + validity.inSeconds;
    if (nowSeconds > expiresAt || expiresAt > hardLimit) {
      return ResetAuthorizationStatus.expired;
    }
    return ResetAuthorizationStatus.valid;
  }
}
