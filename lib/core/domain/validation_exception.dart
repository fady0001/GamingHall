/// خطأ "متوقَّع" سببه مدخلات أو حالة لا تسمح بالعملية (اسم ناقص، مبلغ صفري،
/// عنصر محذوف...). رسالته عربية جاهزة للعرض للمستخدم كما هي.
///
/// نستعمله بدل [StateError] لأن [StateError] معناه "خلل في البرنامج"، فيوقف
/// المنقّح (debugger) عنده ويلتبس مع الأخطاء الحقيقية.
class ValidationException implements Exception {
  final String message;
  const ValidationException(this.message);

  @override
  String toString() => message;
}
