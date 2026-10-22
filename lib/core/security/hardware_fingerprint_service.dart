import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// يولّد "كود الجهاز" الذي يُرسَل للدعم الفني لإصدار ملف التفعيل.
///
/// يعتمد على MachineGuid الخاص بويندوز (ثابت ما دام النظام لم يُعَد تثبيته)،
/// ولا يعتمد على عنوان MAC عمدًا: بطاقات الشبكة/الوايرليس تتغيّر وتتعطّل،
/// وكان ذلك سيؤدي لقفل التطبيق على صالة تعمل بشكل طبيعي.
class HardwareFingerprintService {
  HardwareFingerprintService._();

  /// بصيغة XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX
  static Future<String> computeFingerprint() async {
    final guid = await _readMachineGuid() ?? await _readSystemUuid();
    if (guid == null || guid.isEmpty) {
      throw StateError('تعذّر قراءة معرّف الجهاز من النظام.');
    }
    final digest = sha256.convert(utf8.encode('GL1|${guid.toLowerCase()}'));
    final hex = digest.toString().substring(0, 32).toUpperCase();
    return [
      hex.substring(0, 8),
      hex.substring(8, 16),
      hex.substring(16, 24),
      hex.substring(24, 32),
    ].join('-');
  }

  static Future<String?> _readMachineGuid() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (result.exitCode != 0) return null;
      final match = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)')
          .firstMatch(result.stdout.toString());
      return match?.group(1);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readSystemUuid() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystemProduct).UUID',
        ],
      );
      if (result.exitCode != 0) return null;
      final out = result.stdout.toString().trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}
