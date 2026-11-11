import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../domain/entities/inventory_models.dart';
import '../cubit/inventory_cubit.dart';
import 'fields.dart';

Future<bool> showStockAdjustDialog(BuildContext context, StockRow row) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _StockAdjustDialog(row: row),
  );
  return ok ?? false;
}

class _StockAdjustDialog extends StatefulWidget {
  final StockRow row;
  const _StockAdjustDialog({required this.row});

  @override
  State<_StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<_StockAdjustDialog> {
  static const _reasons = ['تلف', 'هدية', 'خطأ إدخال', 'استهلاك داخلي', 'ضياع'];

  final _qty = TextEditingController();
  final _reason = TextEditingController();
  StockAdjustMode _mode = StockAdjustMode.increase;
  String? _qtyError;
  String? _reasonError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// الكمية بعد التعديل (للمعاينة)، أو null إن لم يُدخل رقم صالح.
  int? get _result {
    final q = parseIntField(_qty.text);
    if (q == null) return null;
    final now = widget.row.onHand;
    switch (_mode) {
      case StockAdjustMode.increase:
        return now + q;
      case StockAdjustMode.decrease:
        return now - q;
      case StockAdjustMode.setTo:
        return q;
    }
  }

  Future<void> _submit() async {
    final q = parseIntField(_qty.text);
    final reason = _reason.text.trim();
    setState(() {
      _error = null;
      _qtyError = q == null
          ? 'أدخل الكمية'
          : (_mode != StockAdjustMode.setTo && q == 0 ? 'أدخل عددًا أكبر من صفر' : null);
      _reasonError = reason.isEmpty ? 'اكتب سبب التعديل أو اختر واحدًا' : null;
    });
    if (_qtyError != null || _reasonError != null) return;

    setState(() => _busy = true);
    try {
      await context.read<InventoryCubit>().adjustStock(
            itemId: widget.row.itemId,
            mode: _mode,
            quantity: q!,
            reason: reason,
          );
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
    final row = widget.row;
    final result = _result;
    return AppDialog(
      title: 'تعديل مخزون: ${row.name}',
      icon: Icons.edit_note_rounded,
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
          label: const Text('حفظ التعديل'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            row.started
                ? 'الكمية الحالية: ${row.onHand} قطعة'
                : 'لم يبدأ تتبّع هذا الصنف بعد (الكمية الحالية 0).',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: const Text('زيادة'),
                selected: _mode == StockAdjustMode.increase,
                onSelected: _busy ? null : (_) => setState(() => _mode = StockAdjustMode.increase),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.remove_rounded, size: 18),
                label: const Text('نقص'),
                selected: _mode == StockAdjustMode.decrease,
                onSelected: _busy ? null : (_) => setState(() => _mode = StockAdjustMode.decrease),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('ضبط على رقم'),
                selected: _mode == StockAdjustMode.setTo,
                onSelected: _busy ? null : (_) => setState(() => _mode = StockAdjustMode.setTo),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          IntField(
            controller: _qty,
            label: _mode == StockAdjustMode.setTo ? 'الكمية الجديدة' : 'العدد (قطع)',
            icon: Icons.numbers_rounded,
            errorText: _qtyError,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            result == null ? 'الكمية بعد التعديل: —' : 'الكمية بعد التعديل: $result قطعة',
            style: AppTextStyles.bodyMedium(
                (result != null && result < 0) ? AppColors.danger : AppColors.secondary),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Text('السبب (إلزامي)', style: AppTextStyles.label()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _reasons)
                ActionChip(
                  label: Text(r),
                  onPressed: _busy ? null : () => setState(() => _reason.text = r),
                ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceS),
          TextField(
            controller: _reason,
            enabled: !_busy,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'السبب',
              prefixIcon: const Icon(Icons.notes_rounded),
              errorText: _reasonError,
              counterText: '',
            ),
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
