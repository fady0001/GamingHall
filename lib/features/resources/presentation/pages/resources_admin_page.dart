import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/page_header.dart';
import '../../domain/entities/resource_kind.dart';
import '../cubit/resources_cubit.dart';
import 'resource_category_page.dart';

/// "الأجهزة والأسعار" (للمدير فقط): أربع كاردات، كل كارد يفتح صفحة قسمه
/// (بلايستيشن، كمبيوتر، طاولات، ألعاب أخرى) لإضافة ما عندك وتحديد الأسعار.
class ResourcesAdminPage extends StatelessWidget {
  const ResourcesAdminPage({super.key});

  String _subtitle(ResourceGroup g) {
    switch (g) {
      case ResourceGroup.consoles:
        return 'شاشات البلايستيشن وأسعارها حسب عدد اللاعبين';
      case ResourceGroup.computers:
        return 'الكمبيوترات وسعر الساعة لكل منها';
      case ResourceGroup.tables:
        return 'الطاولات وأنواعها (بلياردو، هوكي...)';
      case ResourceGroup.other:
        return 'أي ألعاب أخرى عندك وسعر ساعتها';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ResourcesCubit>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'الأجهزة والأسعار',
          subtitle: 'اختر القسم لإضافة ما عندك وتحديد الأسعار',
        ),
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : GridView(
                  padding: const EdgeInsets.fromLTRB(
                      Dimensions.spaceL, 0, Dimensions.spaceL, Dimensions.spaceL),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 460,
                    mainAxisExtent: 170,
                    crossAxisSpacing: Dimensions.spaceM,
                    mainAxisSpacing: Dimensions.spaceM,
                  ),
                  children: [
                    for (final group in ResourceGroup.values)
                      _CategoryCard(
                        group: group,
                        subtitle: _subtitle(group),
                        count: state.resources.where((r) => r.kind.group == group).length,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ResourceCategoryPage(group: group),
                        )),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ResourceGroup group;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.group,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Dimensions.spaceL),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(Dimensions.radiusL),
            ),
            child: Icon(group.icon, size: 38, color: AppColors.primaryLight),
          ),
          const SizedBox(width: Dimensions.spaceL),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.label, style: AppTextStyles.heading2()),
                const SizedBox(height: 4),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall()),
                const SizedBox(height: 8),
                Text(
                  count == 0 ? 'لا يوجد شيء بعد' : 'العدد: $count',
                  style: AppTextStyles.bodyMedium(
                      count == 0 ? AppColors.textMuted : AppColors.secondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
