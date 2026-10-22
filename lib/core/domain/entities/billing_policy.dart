import '../value_objects/money.dart';

/// قواعد الحساب التي يحدّدها المدير من الإعدادات.
class BillingPolicy {
  /// أقل مبلغ يمكن أن تصدر به فاتورة غير فارغة (مثلاً 5000 ل.س).
  final Money minimumInvoice;

  /// تقريب المبلغ النهائي لأقرب مضاعف لهذه القيمة (1 = بدون تقريب).
  final int roundingStep;

  const BillingPolicy({
    this.minimumInvoice = const Money(5000),
    this.roundingStep = 1,
  });
}
