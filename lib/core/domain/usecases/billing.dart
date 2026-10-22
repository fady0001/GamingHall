import '../entities/billing_policy.dart';
import '../value_objects/money.dart';

/// الدقائق المحتسبة: الوقت الفعلي مقرَّب لأقرب دقيقة (30 ثانية فأكثر تُحسب
/// دقيقة كاملة). لا يوجد أي تقريب لفئات أكبر (ربع ساعة...) بحسب قاعدة العمل.
int billedMinutesFor(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  if (seconds <= 0) return 0;
  return (seconds + 30) ~/ 60;
}

/// أجر خط لعب واحد = سعر الساعة × الدقائق ÷ 60، مقرَّب لأقرب ليرة.
Money chargeForMinutes({required Money hourlyRate, required int minutes}) {
  if (minutes <= 0) return Money.zero;
  return Money((hourlyRate.amount * minutes + 30) ~/ 60);
}

/// تقريب المبلغ لأقرب مضاعف للخطوة [step] (نصف يُقرَّب للأعلى).
int roundToStep(int amount, int step) {
  if (step <= 1) return amount;
  return ((amount + step ~/ 2) ~/ step) * step;
}

int _ceilToStep(int amount, int step) {
  if (step <= 1) return amount;
  return ((amount + step - 1) ~/ step) * step;
}

/// تفصيل مجاميع الفاتورة.
class InvoiceTotals {
  final Money playTotal;
  final Money itemsTotal;

  /// المجموع قبل أي تعويض أو تقريب.
  final Money subtotal;

  /// ما أُضيف لبلوغ الحد الأدنى للفاتورة (صفر غالبًا).
  final Money minimumAdjustment;

  /// فرق التقريب (قد يكون سالبًا أو موجبًا أو صفرًا).
  final int roundingDelta;

  final Money finalTotal;

  const InvoiceTotals({
    required this.playTotal,
    required this.itemsTotal,
    required this.subtotal,
    required this.minimumAdjustment,
    required this.roundingDelta,
    required this.finalTotal,
  });

  static const InvoiceTotals empty = InvoiceTotals(
    playTotal: Money.zero,
    itemsTotal: Money.zero,
    subtotal: Money.zero,
    minimumAdjustment: Money.zero,
    roundingDelta: 0,
    finalTotal: Money.zero,
  );
}

/// يحسب مجاميع الفاتورة: لعب + مشتريات، ثم الحد الأدنى، ثم التقريب.
/// الفاتورة الفارغة (بلا لعب ولا مشتريات) مجموعها صفر ولا يُطبَّق عليها الحد الأدنى.
InvoiceTotals computeInvoiceTotals({
  required List<Money> playCharges,
  required List<Money> itemTotals,
  required BillingPolicy policy,
}) {
  if (playCharges.isEmpty && itemTotals.isEmpty) return InvoiceTotals.empty;

  final play = sumMoney(playCharges);
  final items = sumMoney(itemTotals);
  final subtotal = play + items;

  final minimum = policy.minimumInvoice.amount;
  final adjustment = subtotal.amount < minimum ? minimum - subtotal.amount : 0;
  final base = subtotal.amount + adjustment;

  var finalAmount = roundToStep(base, policy.roundingStep);
  if (finalAmount < minimum) {
    finalAmount = _ceilToStep(minimum, policy.roundingStep);
  }

  return InvoiceTotals(
    playTotal: play,
    itemsTotal: items,
    subtotal: subtotal,
    minimumAdjustment: Money(adjustment),
    roundingDelta: finalAmount - base,
    finalTotal: Money(finalAmount),
  );
}
