import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'hardware_fingerprint_service.dart';
import 'license_public_key.dart';

enum LicenseStatus {
  valid,
  missingLicenseFile,
  fingerprintMismatch,
  corruptLicenseFile,
  fingerprintUnavailable,
}

class LicenseCheckResult {
  final LicenseStatus status;
  final String currentDeviceFingerprint;

  const LicenseCheckResult({
    required this.status,
    required this.currentDeviceFingerprint,
  });

  bool get isValid => status == LicenseStatus.valid;
}

/// ترخيص مقفول على جهاز واحد. الملف موقَّع بمفتاح خاص (Ed25519) لا يوجد في
/// التطبيق، والتطبيق يحمل المفتاح العام فقط: فحتى لو فُكّ التطبيق بالكامل لا
/// يمكن توليد ترخيص صالح لجهاز آخر.
class LicenseService {
  LicenseService._();

  static const String _licenseFileName = 'license.lic';

  /// الرسالة التي يوقّعها المطوّر: يجب أن تطابق tool/license_tool.dart.
  static String signedMessage(String fingerprint) => 'GL1:$fingerprint';

  static Future<LicenseCheckResult> validate() async {
    final String fingerprint;
    try {
      fingerprint = await HardwareFingerprintService.computeFingerprint();
    } catch (_) {
      return const LicenseCheckResult(
        status: LicenseStatus.fingerprintUnavailable,
        currentDeviceFingerprint: '—',
      );
    }

    LicenseCheckResult result(LicenseStatus s) => LicenseCheckResult(
          status: s,
          currentDeviceFingerprint: fingerprint,
        );

    final file = await _licenseFile();
    if (!await file.exists()) return result(LicenseStatus.missingLicenseFile);

    String storedFingerprint;
    List<int> signatureBytes;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      storedFingerprint = (data['fingerprint'] as String).trim();
      signatureBytes = base64.decode(data['signature'] as String);
    } catch (_) {
      return result(LicenseStatus.corruptLicenseFile);
    }

    final bool authentic;
    try {
      final publicKey = SimplePublicKey(
        base64.decode(LicensePublicKey.base64Value),
        type: KeyPairType.ed25519,
      );
      authentic = await Ed25519().verify(
        utf8.encode(signedMessage(storedFingerprint)),
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
    } catch (_) {
      return result(LicenseStatus.corruptLicenseFile);
    }

    if (!authentic) return result(LicenseStatus.corruptLicenseFile);
    if (storedFingerprint != fingerprint) {
      return result(LicenseStatus.fingerprintMismatch);
    }
    return result(LicenseStatus.valid);
  }

  /// ينسخ ملف ترخيص اختاره المستخدم إلى مكانه الصحيح ثم يتحقق منه.
  static Future<LicenseCheckResult> installFrom(String sourcePath) async {
    final target = await _licenseFile();
    await Directory(p.dirname(target.path)).create(recursive: true);
    await File(sourcePath).copy(target.path);
    return validate();
  }

  static Future<File> _licenseFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _licenseFileName));
  }

  static Future<String> licenseFilePath() async => (await _licenseFile()).path;
}
