// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

/// أداة المطوّر لإدارة التراخيص. لا تُرفَق مع التطبيق المُسلَّم للعميل.
///
/// 1) توليد زوج مفاتيح (مرة واحدة فقط، واحتفظ بالمفتاح الخاص بأمان):
///      dart run tool/license_tool.dart keygen
///    ثم ضع المفتاح العام في lib/core/security/license_public_key.dart
///
/// 2) إصدار ترخيص لجهاز عميل (الكود تراه العميل في شاشة التفعيل):
///      dart run tool/license_tool.dart sign <كود_الجهاز> <مسار_ملف_المفتاح_الخاص>
///    الناتج: license.lic في المجلد الحالي، يُرسَل للعميل.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(64);
  }

  switch (args.first) {
    case 'keygen':
      await _keygen();
    case 'sign':
      if (args.length < 3) {
        _usage();
        exit(64);
      }
      await _sign(args[1].trim(), args[2].trim());
    default:
      _usage();
      exit(64);
  }
}

void _usage() {
  print('الاستخدام:');
  print('  dart run tool/license_tool.dart keygen');
  print('  dart run tool/license_tool.dart sign <كود_الجهاز> <ملف_المفتاح_الخاص>');
}

Future<void> _keygen() async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final privateBytes = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  File('license_private_key.txt').writeAsStringSync('${base64.encode(privateBytes)}\n');
  print('تم إنشاء المفتاح الخاص في: ${File('license_private_key.txt').absolute.path}');
  print('احتفظ به بأمان ولا تضعه داخل المشروع ولا ترفعه إلى GitHub.');
  print('');
  print('المفتاح العام (ضعه في lib/core/security/license_public_key.dart):');
  print(base64.encode(publicKey.bytes));
}

Future<void> _sign(String fingerprint, String privateKeyPath) async {
  final seed = base64.decode(File(privateKeyPath).readAsStringSync().trim());
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);

  final signature = await algorithm.sign(
    utf8.encode('GL1:$fingerprint'),
    keyPair: keyPair,
  );

  final license = jsonEncode({
    'v': 1,
    'fingerprint': fingerprint,
    'issuedAt': DateTime.now().toIso8601String(),
    'signature': base64.encode(signature.bytes),
  });
  File('license.lic').writeAsStringSync(license);
  print('تم إنشاء ملف الترخيص: ${File('license.lic').absolute.path}');
  print('أرسله للعميل ليضعه في مجلد التطبيق (أو يختاره من شاشة التفعيل).');
}
