import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../domain/entities/game_resource.dart';
import '../../domain/entities/resource_kind.dart';
import '../cubit/resources_cubit.dart';
import '../widgets/resource_form_dialog.dart';
import '../widgets/resource_row.dart';
import '../widgets/table_types_section.dart';

/// صفحة قسم واحد (بلايستيشن / كمبيوتر / طاولات / ألعاب أخرى): تضيف فيها ما
/// عندك من هذا القسم وتحدد أسعاره. صفحة الطاولات فيها أيضًا إدارة الأنواع.
class ResourceCategoryPage extends StatelessWidget {
  final ResourceGroup group;
  const ResourceCategoryPage({super.key, required this.group});

  ResourceKind get _kind => resourceKindOfGroup(group);

  String get _addLabel {
    switch (group) {
      case ResourceGroup.consoles:
        return 'إضافة شاشة بلايستيشن';
      case ResourceGroup.computers:
        return 'إضافة كمبيوتر';
      case ResourceGroup.tables:
        return 'إضافة طاولة';
      case ResourceGroup.other:
        return 'إضافة لعبة';
    }
  }

  String get _emptyText {
    switch (group) {
      case ResourceGroup.consoles:
        return 'لا توجد شاشات بلايستيشن بعد. اضغط "$_addLabel" لإضافة أول شاشة.';
      case ResourceGroup.computers:
        return 'لا توجد كمبيوترات بعد. اضغط "$_addLabel" لإضافة أول كمبيوتر.';
      case ResourceGroup.tables:
        return 'لا توجد طاولات بعد. أضف نوع الطاولة أولًا ثم اضغط "$_addLabel".';
      case ResourceGroup.other:
        return 'لا توجد ألعاب أخرى بعد. اضغط "$_addLabel" لإضافة أول لعبة.';
    }
  }

  void _add(BuildContext context) {
    // الطاولة تحتاج نوعًا واحدًا على الأقل.
    if (group == ResourceGroup.tables &&
        context.read<ResourcesCubit>().state.tableTypes.isEmpty) {
      showAppSnack(context, 'أضف نوع طاولة أولًا (مثل بلياردو) من قسم "أنواع الطاولات"',
          error: true);
      return;
    }
    showResourceFormDialog(context, kind: _kind);
  }

  Future<void> _toggleService(BuildContext context, GameResource r, bool outOfService) async {
    try {
      // الإخراج من الخدمة ممنوع إن كان عليه لعب جارٍ أو حجز (يُفحص أيضًا داخل قاعدة البيانات).
      if (outOfService) {
        final reason = await context
            .read<ResourcesCubit>()
            .blockReason(r.id, forDelete: false);
        if (reason != null) {
          if (context.mounted) showAppSnack(context, reason, error: true);
          return;
        }
      }
      if (!context.mounted) return;
      await context.read<ResourcesCubit>().setOutOfService(r.id, outOfService);
      if (context.mounted) {
        showAppSnack(
          context,
          outOfService ? '"${r.name}" أصبح خارج الخدمة' : '"${r.name}" عاد إلى الخدمة',
        );
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(BuildContext context, GameResource r) async {
    // الحذف ممنوع إن كان عليه لعب جارٍ أو حجز: نبلّغ فورًا قبل سؤال التأكيد.
    final reason =
        await context.read<ResourcesCubit>().blockReason(r.id, forDelete: true);
    if (reason != null) {
      if (context.mounted) showAppSnack(context, reason, error: true);
      return;
    }
    if (!context.mounted) return;
    final ok = await showConfirmDialog(
      context,
      title: 'حذف "${r.name}"؟',
      message: 'سيختفي من لوحة الأجهزة. الفواتير القديمة التي استخدمته تبقى سليمة.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<ResourcesCubit>().remove(r.id);
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ResourcesCubit>().state;
    final items = state.resources.where((r) => r.kind.group == group).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: group.label,
              subtitle: 'أضف ما عندك وحدّد سعر الساعة لكل واحد',
              leading: IconButton(
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              actions: [
                SizedBox(
                  height: Dimensions.buttonHeightLarge,
                  child: FilledButton.icon(
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_addLabel),
                  ),
                ),
              ],
            ),
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          Dimensions.spaceL, 0, Dimensions.spaceL, Dimensions.spaceL),
                      children: [
                        if (group == ResourceGroup.tables) ...[
                          const TableTypesSection(),
                          const SizedBox(height: Dimensions.spaceL),
                          Text('الطاولات (${items.length})',
                              style: AppTextStyles.heading3()),
                          const SizedBox(height: Dimensions.spaceS),
                        ],
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Dimensions.spaceM),
                            child: Text(_emptyText,
                                style: AppTextStyles.bodyMedium(AppColors.textMuted)),
                          ),
                        for (final r in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
                            child: ResourceRow(
                              resource: r,
                              onEdit: () => showResourceFormDialog(context, existing: r),
                              onToggle: (v) => _toggleService(context, r, v),
                              onDelete: () => _delete(context, r),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// الفئة التي يُضاف إليها الجهاز من صفحة القسم.
ResourceKind resourceKindOfGroup(ResourceGroup g) {
  switch (g) {
    case ResourceGroup.consoles:
      return ResourceKind.playstation;
    case ResourceGroup.computers:
      return ResourceKind.computer;
    case ResourceGroup.tables:
      return ResourceKind.table;
    case ResourceGroup.other:
      return ResourceKind.other;
  }
}
