import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/arabic_search.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../menu/domain/entities/menu_category.dart';
import '../../../menu/domain/entities/menu_item_entity.dart';
import '../../../menu/presentation/cubit/menu_cubit.dart';
import '../cubit/invoices_cubit.dart';

/// لوحة المنيو داخل الفاتورة: بحث + تبويبات التصنيفات، والنقرة على أي صنف
/// تضيفه (النقرات المتكررة تزيد الكمية).
class MenuPickerPanel extends StatefulWidget {
  final int invoiceId;

  /// true: اللوحة تأخذ ارتفاع محتواها (للاستخدام داخل صفحة قابلة للتمرير في
  /// الشاشات الضيقة). false: تملأ المساحة المتاحة وشبكتها تتمرر لوحدها.
  final bool shrinkWrap;
  const MenuPickerPanel({
    super.key,
    required this.invoiceId,
    this.shrinkWrap = false,
  });

  @override
  State<MenuPickerPanel> createState() => _MenuPickerPanelState();
}

class _MenuPickerPanelState extends State<MenuPickerPanel> {
  MenuCategory? _category;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add(MenuItemEntity item) async {
    try {
      await context.read<InvoicesCubit>().addItem(
        invoiceId: widget.invoiceId,
        menuItemId: item.id,
      );
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MenuCubit>().state;
    final q = normalizeForSearch(_search.text);

    final available = MenuCategory.values
        .where((c) => state.items.any((i) => i.category == c))
        .toList();

    final items = state.items.where((i) {
      if (q.isNotEmpty) return normalizeForSearch(i.name).contains(q);
      return _category == null || i.category == _category;
    }).toList();

    if (!state.isLoading && state.items.isEmpty) {
      const empty = EmptyState(
        icon: Icons.restaurant_menu_rounded,
        title: 'قائمة المشتريات فارغ',
        message: 'أضف المأكولات والمشروبات من صفحة "قائمة المشتريات".',
      );
      return widget.shrinkWrap
          ? const SizedBox(height: 240, child: empty)
          : empty;
    }

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 170,
      mainAxisExtent: 92,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    );

    final Widget results = items.isEmpty
        ? const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'لا توجد نتائج',
          )
        : GridView.builder(
            gridDelegate: gridDelegate,
            // داخل صفحة تمرير: الشبكة بحجم محتواها ولا تتمرر وحدها.
            shrinkWrap: widget.shrinkWrap,
            physics: widget.shrinkWrap
                ? const NeverScrollableScrollPhysics()
                : null,
            itemCount: items.length,
            itemBuilder: (context, i) =>
                _MenuTile(item: items[i], onTap: () => _add(items[i])),
          );

    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'ابحث في قائمة المشتريات...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: Dimensions.spaceS),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: const Text('الكل'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
              ),
              for (final c in available)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    avatar: Icon(c.icon, size: 16),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Dimensions.spaceS),
        if (widget.shrinkWrap)
          (items.isEmpty ? SizedBox(height: 180, child: results) : results)
        else
          Expanded(child: results),
      ],
    );
  }
}

class _MenuTile extends StatefulWidget {
  final MenuItemEntity item;
  final VoidCallback onTap;
  const _MenuTile({required this.item, required this.onTap});

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceHighest : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(Dimensions.radiusM),
            border: Border.all(
              color: _hovered ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.category.icon, size: 18, color: AppColors.accent),
                  const Spacer(),
                  Icon(
                    Icons.add_circle_rounded,
                    size: 20,
                    color: AppColors.primaryLight,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium().copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                formatMoneyWithUnit(item.price),
                style: AppTextStyles.bodySmall(AppColors.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
