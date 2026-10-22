/// معلومات عامة عن التطبيق. الاسم عام عمدًا (لا يرتبط بأي صالة بعينها)،
/// واسم الصالة الذي يظهر على الفاتورة يُضبط من شاشة الإعدادات.
class AppInfo {
  AppInfo._();

  static const String englishName = 'Gaming Hall';
  static const String arabicName = 'صالة ألعاب';
  static const String tagline = 'نظام إدارة صالات الألعاب';
  static const String version = '1.0.0';

  static const String currencyLabel = 'ل.س';
  static const String databaseFileName = 'gaming_hall.db';

  /// اسم الصالة الافتراضي على الفاتورة قبل أن يضبطه المدير.
  static const String defaultInvoiceTitle = 'صالة ألعاب';
  static const String defaultInvoiceFooter = 'شكرًا لزيارتكم';
}
