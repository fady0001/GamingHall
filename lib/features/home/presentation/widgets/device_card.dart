import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/live_builder.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../resources/domain/entities/resource_status.dart';
import '../../../resources/domain/usecases/build_resource_views.dart';
import '../../../resources/domain/entities/resource_kind.dart';

/// بطاقة جهاز/طاولة: اسم + حالة (لون + أيقونة + نص) + تفاصيل حسب الحالة.
class DeviceCard extends StatelessWidget {
  final ResourceView view;
  final VoidCallback onTap;

  const DeviceCard({super.key, required this.view, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = view.resource;
    final color = AppColors.forStatus(view.status);
    final dimmed = view.status == ResourceStatus.outOfService;

    return AppCard(
      onTap: onTap,
      accentColor: color,
      glow: view.status == ResourceStatus.busy,
      padding: const EdgeInsets.all(Dimensions.spaceM),
      child: Opacity(
        opacity: dimmed ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(r.icon, color: color, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading3()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StatusBadge(label: view.status.label, color: color, icon: view.status.icon),
            const Spacer(),
            _details(),
          ],
        ),
      ),
    );
  }

  Widget _details() {
    switch (view.status) {
      case ResourceStatus.busy:
        final line = view.runningLine!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(view.runningInvoice?.customerName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium().copyWith(fontWeight: FontWeight.w700)),
            LiveBuilder(
              builder: (context, now) => line.isFixed
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatDuration(line.remainingAt(now)!),
                          textDirection: TextDirection.ltr,
                          style: AppTextStyles.timer(
                              line.remainingAt(now)!.inMinutes < 5
                                  ? AppColors.warning
                                  : AppColors.secondary,
                              22),
                        ),
                        Text('متبقٍ من وقت محدد',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall()),
                      ],
                    )
                  : Text(
                      formatDuration(line.elapsedAt(now)),
                      textDirection: TextDirection.ltr,
                      style: AppTextStyles.timer(AppColors.secondary, 22),
                    ),
            ),
          ],
        );
      case ResourceStatus.reserved:
        final b = view.upcomingBooking!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium().copyWith(fontWeight: FontWeight.w700)),
            Text('حجز ${b.timeRangeLabel}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall(AppColors.warning)),
          ],
        );
      case ResourceStatus.outOfService:
        return Text('لا يمكن تشغيله حاليًا',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall(AppColors.textMuted));
      case ResourceStatus.available:
        return Text(
            '${view.resource.kind.hasPlayerPricing ? 'من ' : ''}${formatMoney(view.resource.hourlyRates.first)} ل.س / ساعة',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall(AppColors.textSecondary));
    }
  }
}
