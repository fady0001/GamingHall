import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../domain/entities/resource_type.dart';
import '../cubit/resources_cubit.dart';
import 'table_type_dialog.dart';

/// قسم "أنواع الطاولات" داخل صفحة الطاولات. يبدأ فارغًا؛ يضيف المدير أنواعه
/// مرة واحدة (بلياردو، هوكي...) فتبقى محفوظة ويعدّلها أو يحذفها متى شاء.
/// الأنواع نصوص فقط بلا أيقونات.
class TableTypesSection extends StatelessWidget {
  const TableTypesSection({super.key});

  Future<void> _delete(BuildContext context, ResourceType t) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف النوع "${t.name}"؟',
      message: 'يمكن حذف النوع فقط إن لم تكن عندك طاولات من هذا النوع.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<ResourcesCubit>().removeType(t.id);
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = context.watch<ResourcesCubit>().state.tableTypes;

    return AppCard(
      padding: const EdgeInsets.all(Dimensions.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('أنواع الطاولات (${types.length})',
                    style: AppTextStyles.heading3()),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showTableTypeDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة نوع'),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceS),
          if (types.isEmpty)
            Text(
              'لا توجد أنواع بعد. أضف أنواع الطاولات التي عندك (مثل بلياردو أو هوكي) '
              'مرة واحدة، وستظهر دائمًا عند إضافة أي طاولة.',
              style: AppTextStyles.bodyMedium(AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in types)
                  Container(
                    padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(Dimensions.radiusM),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.name, style: AppTextStyles.bodyLarge()),
                        IconButton(
                          tooltip: 'تعديل الاسم',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showTableTypeDialog(context, existing: t),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                        ),
                        IconButton(
                          tooltip: 'حذف النوع',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _delete(context, t),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18, color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
