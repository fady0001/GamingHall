import '../../../../core/constants/app_info.dart';
import '../../../../core/domain/entities/billing_policy.dart';
import '../../../../core/domain/value_objects/money.dart';

/// إعدادات يضبطها المدير.
class AppSettings {
  /// اسم الصالة الذي يظهر على الفاتورة (لا يظهر في اسم التطبيق أو أيقونته).
  final String loungeName;
  final String loungePhone;
  final String invoiceFooter;

  /// أقل مبلغ لفاتورة غير فارغة.
  final Money minimumInvoice;

  /// تقريب المبلغ النهائي (1 = بدون تقريب).
  final int roundingStep;

  /// تنبيه تذكيري كل كم دقيقة أثناء اللعب المفتوح: 15 أو 30 أو 60 (0 = متوقف).
  final int reminderIntervalMinutes;

  /// طباعة تلقائية عند إغلاق الفاتورة.
  final bool autoPrint;

  /// اسم الطابعة المفضلة (فارغ = الطابعة الافتراضية في ويندوز).
  final String printerName;

  const AppSettings({
    this.loungeName = AppInfo.defaultInvoiceTitle,
    this.loungePhone = '',
    this.invoiceFooter = AppInfo.defaultInvoiceFooter,
    this.minimumInvoice = const Money(5000),
    this.roundingStep = 1,
    this.reminderIntervalMinutes = 15,
    this.autoPrint = false,
    this.printerName = '',
  });

  BillingPolicy get billingPolicy => BillingPolicy(
        minimumInvoice: minimumInvoice,
        roundingStep: roundingStep,
      );

  AppSettings copyWith({
    String? loungeName,
    String? loungePhone,
    String? invoiceFooter,
    Money? minimumInvoice,
    int? roundingStep,
    int? reminderIntervalMinutes,
    bool? autoPrint,
    String? printerName,
  }) {
    return AppSettings(
      loungeName: loungeName ?? this.loungeName,
      loungePhone: loungePhone ?? this.loungePhone,
      invoiceFooter: invoiceFooter ?? this.invoiceFooter,
      minimumInvoice: minimumInvoice ?? this.minimumInvoice,
      roundingStep: roundingStep ?? this.roundingStep,
      reminderIntervalMinutes:
          reminderIntervalMinutes ?? this.reminderIntervalMinutes,
      autoPrint: autoPrint ?? this.autoPrint,
      printerName: printerName ?? this.printerName,
    );
  }
}
