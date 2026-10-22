import 'package:flutter/material.dart';

import '../../../../core/domain/entities/billing_policy.dart';
import '../../../../core/domain/usecases/billing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/live_builder.dart';
import '../../domain/entities/invoice.dart';

/// ملخص الحساب: المجاميع مع توضيح أي تعويض للحد الأدنى. للفاتورة المفتوحة
/// يتحدّث حيًا كل ثانية.
class InvoiceSummaryCard extends StatelessWidget {
  final Invoice invoice;
  final BillingPolicy policy;

  const InvoiceSummaryCard({super.key, required this.invoice, required this.policy});

  @override
  Widget build(BuildContext context) {
    if (!invoice.isOpen) return _content(invoice.totalsAt(DateTime.now(), policy));
    return LiveBuilder(builder: (context, now) => _content(invoice.totalsAt(now, policy)));
  }

  Widget _content(InvoiceTotals t) {
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.bodyMedium(AppColors.textSecondary))),
              const SizedBox(width: 8),
              Text(value, style: AppTextStyles.price(color ?? AppColors.textPrimary, 15)),
            ],
          ),
        );

    return AppCard(
      accentColor: AppColors.primary,
      glow: true,
      padding: const EdgeInsets.all(Dimensions.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (invoice.playLines.isNotEmpty) row('مجموع اللعب', formatMoneyWithUnit(t.playTotal)),
          if (invoice.itemLines.isNotEmpty) row('مجموع المشتريات', formatMoneyWithUnit(t.itemsTotal)),
          if (t.minimumAdjustment.amount > 0)
            row('تعويض الحد الأدنى للفاتورة', '+${formatMoneyWithUnit(t.minimumAdjustment)}',
                color: AppColors.warning),
          if (t.roundingDelta != 0)
            row('تقريب',
                '${t.roundingDelta > 0 ? '+' : '-'}${groupThousands(t.roundingDelta.abs())} ل.س'),
          const Divider(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(invoice.isOpen ? 'الإجمالي الحالي' : 'الإجمالي',
                  style: AppTextStyles.heading3()),
              const SizedBox(width: 8),
              // الرقم الكبير يصغر تلقائيًا بدل أن يتجاوز عرض البطاقة.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(formatMoneyWithUnit(t.finalTotal),
                      style: AppTextStyles.timer(AppColors.secondary, 30)),
                ),
              ),
            ],
          ),
          if (invoice.isOpen && !invoice.isEmpty && t.minimumAdjustment.amount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'أقل مبلغ لأي فاتورة ${formatMoneyWithUnit(policy.minimumInvoice)}، '
              'لذلك أُضيف الفرق تلقائيًا.',
              style: AppTextStyles.bodySmall(AppColors.warning),
            ),
          ],
          if (invoice.isOpen && invoice.runningLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'الوقت ما زال يعدّ؛ المبلغ يزيد حتى تُوقف اللعب أو تحاسب الفاتورة.',
              style: AppTextStyles.bodySmall(),
            ),
          ],
        ],
      ),
    );
  }
}
