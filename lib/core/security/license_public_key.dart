/// المفتاح العام للتحقق من ملفات الترخيص (Ed25519، بصيغة Base64).
///
/// مهم: هذا مفتاح *عام* ولا يمكن استخدامه لتوليد تراخيص. المفتاح الخاص
/// المقابل يبقى معك أنت فقط (خارج المشروع) ويُستخدم عبر
/// `dart run tool/license_tool.dart sign ...`.
///
/// قبل بيع التطبيق لأول صالة: ولّد زوج مفاتيح خاصًا بك
/// (`dart run tool/license_tool.dart keygen`) واستبدل القيمة أدناه بالمفتاح
/// العام الجديد، ثم أعد بناء التطبيق. راجع README.md.
class LicensePublicKey {
  LicensePublicKey._();

  static const String base64Value = '6aFKYh3cgtRZtzKcezbZ5eOLvXRIF6NET/LldDJ4myM=';
}
