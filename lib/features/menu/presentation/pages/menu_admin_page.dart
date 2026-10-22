import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../domain/entities/menu_category.dart';
import '../../domain/entities/menu_item_entity.dart';
import '../cubit/menu_cubit.dart';
import '../widgets/menu_item_form_dialog.dart';

/// (قائمة المشتريات): المأكولات والمشروبات والأراكيل وأي صنف آخر.
/// متاحة للمدير والموظف بنفس الصلاحيات (إضافة/تعديل/حذف).
class MenuAdminPage extends StatelessWidget {
  const MenuAdminPage({super.key});

  Future<void> _delete(BuildContext context, MenuItemEntity item) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف "${item.name}"؟',
      message: 'سيختفي من قائمة المشتريات. الفواتير القديمة التي طلبته تبقى سليمة.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<MenuCubit>().remove(item.id);
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MenuCubit>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'قائمة المشتريات',
          subtitle: 'المأكولات والمشروبات والأراكيل التي يبيعها الموظف ضمن الفواتير',
          actions: [
            SizedBox(
              height: Dimensions.buttonHeightLarge,
              child: FilledButton.icon(
                onPressed: () => showMenuItemFormDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة صنف'),
              ),
            ),
          ],
        ),
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.items.isEmpty
                  ? EmptyState(
                      icon: Icons.restaurant_menu_rounded,
                      title: 'قائمة المشتريات فارغ',
                      message: 'أضف الأصناف مع أسعارها ليتمكن الموظف من تسجيلها في الفواتير.',
                      action: FilledButton.icon(
                        onPressed: () => showMenuItemFormDialog(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة صنف'),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          Dimensions.spaceL, 0, Dimensions.spaceL, Dimensions.spaceL),
                      children: [
                        for (final c in MenuCategory.values)
                          ..._section(context, c, state.byCategory(c)),
                      ],
                    ),
        ),
      ],
    );
  }

  List<Widget> _section(BuildContext context, MenuCategory c, List<MenuItemEntity> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: Dimensions.spaceS),
        child: Row(
          children: [
            Icon(c.icon, size: 20, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('${c.label} (${items.length})', style: AppTextStyles.heading3()),
            const Spacer(),
            TextButton.icon(
              onPressed: () => showMenuItemFormDialog(context, initialCategory: c),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('إضافة'),
            ),
          ],
        ),
      ),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(item.name, style: AppTextStyles.bodyLarge())),
                Text(formatMoneyWithUnit(item.price),
                    style: AppTextStyles.price(AppColors.secondary, 16)),
                const SizedBox(width: Dimensions.spaceM),
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => showMenuItemFormDialog(context, existing: item),
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => _delete(context, item),
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
