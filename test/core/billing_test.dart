import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/domain/entities/billing_policy.dart';
import 'package:gaming_hall/core/domain/usecases/billing.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';

void main() {
  group('billedMinutesFor (تقريب لأقرب دقيقة)', () {
    test('صفر وسالب = صفر', () {
      expect(billedMinutesFor(Duration.zero), 0);
      expect(billedMinutesFor(const Duration(seconds: -5)), 0);
    });

    test('أقل من 30 ثانية تُهمل، و30 فأكثر تُحسب دقيقة', () {
      expect(billedMinutesFor(const Duration(seconds: 29)), 0);
      expect(billedMinutesFor(const Duration(seconds: 30)), 1);
      expect(billedMinutesFor(const Duration(seconds: 89)), 1);
      expect(billedMinutesFor(const Duration(seconds: 90)), 2);
      expect(billedMinutesFor(const Duration(hours: 1, minutes: 20)), 80);
    });
  });

  group('chargeForMinutes', () {
    test('ساعة كاملة = سعر الساعة', () {
      expect(chargeForMinutes(hourlyRate: const Money(12000), minutes: 60).amount, 12000);
    });

    test('نصف ساعة ونحوها', () {
      expect(chargeForMinutes(hourlyRate: const Money(12000), minutes: 30).amount, 6000);
      expect(chargeForMinutes(hourlyRate: const Money(10000), minutes: 20).amount, 3333);
      expect(chargeForMinutes(hourlyRate: const Money(10000), minutes: 40).amount, 6667);
    });

    test('صفر دقائق = صفر', () {
      expect(chargeForMinutes(hourlyRate: const Money(12000), minutes: 0).amount, 0);
    });
  });

  group('computeInvoiceTotals', () {
    const policy = BillingPolicy(minimumInvoice: Money(5000));

    test('فاتورة فارغة = صفر ولا حد أدنى', () {
      final t = computeInvoiceTotals(playCharges: [], itemTotals: [], policy: policy);
      expect(t.finalTotal.amount, 0);
      expect(t.minimumAdjustment.amount, 0);
    });

    test('لعب دقيقتين فقط بدون مشتريات = 5000', () {
      final t = computeInvoiceTotals(
        playCharges: [chargeForMinutes(hourlyRate: const Money(12000), minutes: 2)],
        itemTotals: [],
        policy: policy,
      );
      expect(t.subtotal.amount, 400);
      expect(t.minimumAdjustment.amount, 4600);
      expect(t.finalTotal.amount, 5000);
    });

    test('لعب قليل + مشتريات تتجاوز الحد = المجموع الفعلي', () {
      final t = computeInvoiceTotals(
        playCharges: [const Money(400)],
        itemTotals: [const Money(7000)],
        policy: policy,
      );
      expect(t.finalTotal.amount, 7400);
      expect(t.minimumAdjustment.amount, 0);
    });

    test('مجموع يساوي الحد الأدنى تمامًا لا يُعوَّض', () {
      final t = computeInvoiceTotals(
        playCharges: [const Money(5000)],
        itemTotals: [],
        policy: policy,
      );
      expect(t.finalTotal.amount, 5000);
      expect(t.minimumAdjustment.amount, 0);
    });

    test('مشتريات فقط أقل من الحد الأدنى تُرفع للحد الأدنى', () {
      final t = computeInvoiceTotals(
        playCharges: [],
        itemTotals: [const Money(2000)],
        policy: policy,
      );
      expect(t.finalTotal.amount, 5000);
    });

    test('تقريب المبلغ النهائي لأقرب 500', () {
      const p = BillingPolicy(minimumInvoice: Money(5000), roundingStep: 500);
      final t = computeInvoiceTotals(
        playCharges: [const Money(7400)],
        itemTotals: [],
        policy: p,
      );
      expect(t.finalTotal.amount, 7500);
      expect(t.roundingDelta, 100);
    });

    test('التقريب لا ينزل بالمبلغ تحت الحد الأدنى', () {
      const p = BillingPolicy(minimumInvoice: Money(5200), roundingStep: 500);
      final t = computeInvoiceTotals(
        playCharges: [const Money(100)],
        itemTotals: [],
        policy: p,
      );
      expect(t.finalTotal.amount >= 5200, isTrue);
      expect(t.finalTotal.amount % 500, 0);
    });

    test('حد أدنى صفر = بدون حد', () {
      const p = BillingPolicy(minimumInvoice: Money(0));
      final t = computeInvoiceTotals(
        playCharges: [const Money(400)],
        itemTotals: [],
        policy: p,
      );
      expect(t.finalTotal.amount, 400);
    });
  });
}
