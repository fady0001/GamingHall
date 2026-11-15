import '../../../../core/domain/value_objects/money.dart';

/// دفعة مسدَّدة لفاتورة مشتريات (مشتريات البوفيه).
///
/// تظهر في صفحة المصاريف **للعرض فقط** حتى تُحسب مع المصاريف؛ إضافتها
/// وتعديلها وحذفها من صفحة المخزون والجرد (فواتير المشتريات) فقط.
/// تُحسب حسب تاريخ الدفع (نفس قاعدة التقرير الشهري).
class BuffetPayment {
  final int id;
  final int invoiceId;
  final Money amount;
  final DateTime paidAt;

  /// بيانات فاتورة المشتريات التي تخصّها الدفعة.
  final String? supplier;
  final String? invoiceNo;
  final DateTime purchasedAt;

  const BuffetPayment({
    required this.id,
    required this.invoiceId,
    required this.amount,
    required this.paidAt,
    required this.supplier,
    required this.invoiceNo,
    required this.purchasedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is BuffetPayment &&
      other.id == id &&
      other.invoiceId == invoiceId &&
      other.amount == amount &&
      other.paidAt == paidAt &&
      other.supplier == supplier &&
      other.invoiceNo == invoiceNo &&
      other.purchasedAt == purchasedAt;

  @override
  int get hashCode =>
      Object.hash(id, invoiceId, amount, paidAt, supplier, invoiceNo, purchasedAt);
}
