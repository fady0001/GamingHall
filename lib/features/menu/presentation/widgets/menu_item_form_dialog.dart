import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/money_field.dart';
import '../../domain/entities/menu_category.dart';
import '../../domain/entities/menu_item_entity.dart';
import '../cubit/menu_cubit.dart';

Future<bool> showMenuItemFormDialog(
  BuildContext context, {
  MenuItemEntity? existing,
  MenuCategory? initialCategory,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _MenuItemFormDialog(existing: existing, initialCategory: initialCategory),
  );
  return ok ?? false;
}

class _MenuItemFormDialog extends StatefulWidget {
  final MenuItemEntity? existing;
  final MenuCategory? initialCategory;
  const _MenuItemFormDialog({this.existing, this.initialCategory});

  @override
  State<_MenuItemFormDialog> createState() => _MenuItemFormDialogState();
}

class _MenuItemFormDialogState extends State<_MenuItemFormDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  late MenuCategory _category;
  String? _nameError;
  String? _priceError;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ?? widget.initialCategory ?? MenuCategory.coldDrinks;
    if (e != null) {
      _name.text = e.name;
      _price.text = formatMoney(e.price);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final price = parseMoney(_price.text);
    setState(() {
      _error = null;
      _nameError = _name.text.trim().isEmpty ? 'اكتب اسم الصنف' : null;
      _priceError = (price == null || price.amount <= 0) ? 'أدخل السعر' : null;
    });
    if (_nameError != null || _priceError != null) return;

    setState(() => _busy = true);
    final cubit = context.read<MenuCubit>();
    try {
      if (_isEdit) {
        await cubit.update(widget.existing!.copyWith(
          name: _name.text.trim(),
          category: _category,
          price: price,
        ));
      } else {
        await cubit.add(MenuItemEntity(
          id: 0,
          name: _name.text.trim(),
          category: _category,
          price: price!,
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
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
      title: _isEdit ? 'تعديل الصنف' : 'إضافة صنف للمنيو',
      icon: _category.icon,
      iconColor: AppColors.accent,
      width: 480,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(_isEdit ? 'حفظ' : 'إضافة'),
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
          MoneyField(
            controller: _price,
            label: 'السعر',
            errorText: _priceError,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
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
