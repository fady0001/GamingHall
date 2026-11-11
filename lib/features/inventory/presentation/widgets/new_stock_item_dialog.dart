import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../menu/domain/entities/menu_category.dart';
import '../cubit/inventory_cubit.dart';

/// صنف جديد من شاشة الشراء. لا يُباع: لا يظهر في قائمة المشتريات ولا في
/// الفواتير، لكنه يدخل المخزون والجرد. يعيد (رقم الصنف، اسمه) أو null.
Future<({int id, String name})?> showNewStockItemDialog(BuildContext context) {
  return showDialog<({int id, String name})>(
    context: context,
    builder: (_) => const _NewStockItemDialog(),
  );
}

class _NewStockItemDialog extends StatefulWidget {
  const _NewStockItemDialog();

  @override
  State<_NewStockItemDialog> createState() => _NewStockItemDialogState();
}

class _NewStockItemDialogState extends State<_NewStockItemDialog> {
  final _name = TextEditingController();
  MenuCategory _category = MenuCategory.other;
  String? _nameError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    setState(() {
      _error = null;
      _nameError = name.isEmpty ? 'اكتب اسم الصنف' : null;
    });
    if (name.isEmpty) return;

    setState(() => _busy = true);
    try {
      final id = await context
          .read<InventoryCubit>()
          .createStockItem(name: name, category: _category);
      if (mounted) Navigator.of(context).pop((id: id, name: name));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'صنف جديد',
      icon: Icons.add_box_rounded,
      iconColor: AppColors.accent,
      width: 460,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('إضافة'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_busy,
            maxLength: 40,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'اسم الصنف',
              prefixIcon: const Icon(Icons.label_rounded),
              errorText: _nameError,
              counterText: '',
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Text('التصنيف', style: AppTextStyles.label()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in MenuCategory.values)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 18),
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: _busy ? null : (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          Text(
            'هذا الصنف لا يُباع: لن يظهر في قائمة المشتريات ولا في الفواتير، لكنه يدخل المخزون والجرد. '
            'لو أردت بيعه لاحقًا فعّل "يُباع" من إعدادات الصنف.',
            style: AppTextStyles.bodySmall(AppColors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceM),
            Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],
        ],
      ),
    );
  }
}
