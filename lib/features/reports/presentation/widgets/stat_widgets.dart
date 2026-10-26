import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_card.dart';

/// بطاقة مؤشر واحد: أيقونة + عنوان + رقم كبير + سطر توضيحي اختياري.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// سطر صغير تحت الرقم يشرح معناه أو يضيف تفصيلًا (مثل اسم أفضل يوم).
  final String? hint;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accentColor: color,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Dimensions.radiusM),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: Dimensions.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      style: AppTextStyles.timer(AppColors.textPrimary, 22)),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// شبكة بطاقات متجاوبة بأحجام متساوية: 3 أعمدة على الشاشات العريضة، 2 على
/// المتوسطة، وعمود واحد على الضيقة.
class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  const KpiGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = Dimensions.spaceM;
        final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}
