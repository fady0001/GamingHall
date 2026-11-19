// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:gaming_hall/core/security/reset_authorization.dart';

/// أداة المطوّر لإدارة التراخيص. لا تُرفَق مع التطبيق المُسلَّم للعميل.
///
/// 1) توليد زوج مفاتيح (مرة واحدة فقط، واحتفظ بالمفتاح الخاص بأمان):
///      dart run tool/license_tool.dart keygen
///    ثم ضع المفتاح العام في lib/core/security/license_public_key.dart
///
/// 2) إصدار ترخيص لجهاز عميل (الكود تراه العميل في شاشة التفعيل):
///      dart run tool/license_tool.dart sign <كود_الجهاز> <مسار_ملف_المفتاح_الخاص>
///    الناتج: license.lic في المجلد الحالي، يُرسَل للعميل.
///
/// 3) عميل فقد كلمة السر ورمز الاسترداد معًا (يرسل لك "رمز الطلب" R1-...):
///      dart run tool/license_tool.dart reset <رمز_الطلب> <مسار_ملف_المفتاح_الخاص>
///    الناتج: رمز تفويض (A1....) يُرسَل للعميل، صالح 24 ساعة ولهذا الجهاز
///    ولهذا الطلب فقط. تحقق من هوية العميل قبل الإصدار. يُسجَّل كل تفويض في
///    reset_log.txt بالمجلد الحالي.
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
    case 'reset':
      if (args.length < 3) {
        _usage();
        exit(64);
      }
      // رمز الطلب قد يصل مقسومًا على أسطر؛ نجمع كل الوسائط بين الأمر والمفتاح.
      final requestText = args.sublist(1, args.length - 1).join();
      await _reset(requestText, args.last.trim());
    default:
      _usage();
      exit(64);
  }
}

void _usage() {
  print('الاستخدام:');
  print('  dart run tool/license_tool.dart keygen');
  print('  dart run tool/license_tool.dart sign <كود_الجهاز> <ملف_المفتاح_الخاص>');
  print('  dart run tool/license_tool.dart reset <رمز_الطلب> <ملف_المفتاح_الخاص>');
}

/// يوقّع طلب إعادة تعيين كلمة سر المدير ويطبع رمز التفويض.
Future<void> _reset(String requestText, String privateKeyPath) async {
  final request = ResetRequest.tryParse(requestText);
  if (request == null) {
    print('رمز الطلب غير صالح. يجب أن يبدأ بـ R1- وأن تنسخه كاملًا كما وصلك.');
    exit(65);
  }

  final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final age = nowSeconds - request.issuedAt;
  if (age > ResetRequest.maxAge.inSeconds) {
    print('هذا الطلب أقدم من ${ResetRequest.maxAge.inDays} أيام. '
        'اطلب من العميل إنشاء طلب جديد ("طلب جديد" في نافذة فقدت رمز الاسترداد).');
    exit(65);
  }
  if (age < -ResetAuthorization.clockSkewSeconds) {
    print('وقت الطلب في المستقبل: ساعة جهاز العميل غير صحيحة. '
        'اطلب منه تصحيح التاريخ والوقت ثم إنشاء طلب جديد.');
    exit(65);
  }

  final issuedLocal = DateTime.fromMillisecondsSinceEpoch(
    request.issuedAt * 1000,
    isUtc: true,
  ).toLocal();
  print('كود الجهاز : ${request.fingerprint}');
  print('وقت الطلب  : $issuedLocal');
  print('تحقق أن كود الجهاز يطابق ترخيص هذا العميل في سجلاتك، وأنك تأكدت من');
  print('هويته (فاتورة الشراء / رقم الترخيص / مكالمة) قبل إرسال الرمز.');
  print('');

  final seed = base64.decode(File(privateKeyPath).readAsStringSync().trim());
  final token = await ResetAuthorization.issue(
    request: request,
    privateKeySeed: seed,
  );

  File('reset_log.txt').writeAsStringSync(
    '${DateTime.now().toIso8601String()}  ${request.fingerprint}  '
    'nonce=${request.nonce}\n',
    mode: FileMode.append,
  );

  print('رمز التفويض (صالح ${ResetAuthorization.validity.inHours} ساعة، لمرة واحدة):');
  print(token);
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
