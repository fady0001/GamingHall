import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/live_builder.dart';
import '../../../invoices/domain/entities/invoice.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../resources/domain/entities/resource_kind.dart';

/// بطاقة فاتورة في قائمة الرئيسية. المفتوحة: عدّادات حيّة. المغلقة: الإجمالي.
class InvoiceCard extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onTap;
  const InvoiceCard({super.key, required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final policy = context.watch<SettingsCubit>().state.settings.billingPolicy;
    final running = invoice.runningLines;

    return AppCard(
      onTap: onTap,
      accentColor: invoice.isOpen && running.isNotEmpty ? AppColors.statusBusy : null,
      padding: const EdgeInsets.all(Dimensions.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('#${invoice.id}', style: AppTextStyles.label()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(invoice.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading3()),
              ),
              if (invoice.isOpen)
                LiveBuilder(
                  builder: (context, now) => Text(
                    formatMoneyWithUnit(invoice.totalsAt(now, policy).finalTotal),
                    style: AppTextStyles.price(AppColors.secondary, 18),
                  ),
                )
              else
                Text(formatMoneyWithUnit(invoice.totalsAt(DateTime.now(), policy).finalTotal),
                    style: AppTextStyles.price(AppColors.textPrimary, 18)),
            ],
          ),
          const SizedBox(height: 8),
          if (invoice.isOpen && running.isNotEmpty)
            for (final line in running)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(iconForTypeName(line.typeKey, line.resourceKind),
                        size: 16, color: AppColors.statusBusy),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${line.resourceName}${line.resourceKind == ResourceKind.playstation ? ' • ${line.playerCount} ${line.playerCount == 1 ? 'لاعب' : 'لاعبين'}' : ''}${line.isFixed ? ' • وقت محدد' : ''}',
                        style: AppTextStyles.bodySmall(AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    LiveBuilder(
                      builder: (context, now) => Text(
                        formatDuration(line.isFixed ? line.remainingAt(now)! : line.elapsedAt(now)),
                        textDirection: TextDirection.ltr,
                        style: AppTextStyles.price(AppColors.textPrimary, 14),
                      ),
                    ),
                  ],
                ),
              )
          else
            Text(
              invoice.isOpen
                  ? (invoice.isEmpty ? 'فاتورة جديدة بدون أي طلب' : _summary(invoice))
                  : '${_summary(invoice)} • أُغلقت ${formatClock(invoice.closedAt ?? invoice.createdAt)}',
              style: AppTextStyles.bodySmall(),
            ),
        ],
      ),
    );
  }

  String _summary(Invoice i) {
    final parts = <String>[];
    if (i.playLines.isNotEmpty) parts.add('${i.playLines.length} لعب');
    if (i.itemLines.isNotEmpty) {
      parts.add('${i.itemLines.fold<int>(0, (s, l) => s + l.quantity)} صنف');
    }
    return parts.isEmpty ? '—' : parts.join(' • ');
  }
}
