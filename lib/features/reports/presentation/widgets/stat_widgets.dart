import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_card.dart';

/// بطاقة مؤشر رئيسي (رقم كبير + عنوان).
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
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
              children: [
                Text(label, style: AppTextStyles.bodySmall()),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, style: AppTextStyles.timer(AppColors.textPrimary, 22)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BarDatum {
  final String label;
  final int value;
  final String valueLabel;
  const BarDatum(this.label, this.value, this.valueLabel);
}

/// رسم أعمدة بسيط (بدون مكتبات خارجية): عمود لكل عنصر مع قيمته فوقه.
class SimpleBarChart extends StatelessWidget {
  final List<BarDatum> data;
  final Color color;
  final double height;

  const SimpleBarChart({
    super.key,
    required this.data,
    this.color = AppColors.primary,
    this.height = 190,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<int>(0, (m, d) => d.value > m ? d.value : m);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // نترك مساحة للتسمية السفلية ولقيمة العمود فوقه.
          final barArea = height - 44;
          final minWidth = data.length * 54.0;
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final d in data)
                SizedBox(
                  width: 46,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(d.valueLabel,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: AppTextStyles.bodySmall(AppColors.textSecondary)
                              .copyWith(fontSize: 10)),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: maxValue == 0
                            ? 2
                            : (d.value / maxValue * (barArea - 18)).clamp(2, barArea),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [color.withValues(alpha: 0.55), color],
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(d.label,
                          maxLines: 1,
                          style: AppTextStyles.bodySmall().copyWith(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          );
          if (minWidth > constraints.maxWidth) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minWidth, child: content),
            );
          }
          return content;
        },
      ),
    );
  }
}

/// قائمة ترتيب (1، 2، 3...) مع شريط نسبي لكل عنصر.
class RankList extends StatelessWidget {
  final List<RankItem> items;
  final Color color;
  const RankList({super.key, required this.items, this.color = AppColors.secondary});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('لا توجد بيانات في هذه الفترة', style: AppTextStyles.bodyMedium(AppColors.textMuted)),
      );
    }
    final maxValue = items.fold<int>(0, (m, i) => i.value > m ? i.value : m);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0 ? color : AppColors.surfaceHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Text('${i + 1}',
                          style: AppTextStyles.label(i == 0 ? Colors.black : AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(items[i].title, style: AppTextStyles.bodyMedium(), overflow: TextOverflow.ellipsis)),
                    Text(items[i].valueLabel, style: AppTextStyles.price(AppColors.textPrimary, 14)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: maxValue == 0 ? 0 : items[i].value / maxValue,
                    backgroundColor: AppColors.surfaceHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class RankItem {
  final String title;
  final int value;
  final String valueLabel;
  const RankItem(this.title, this.value, this.valueLabel);
}
