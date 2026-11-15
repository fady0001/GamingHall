import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../domain/entities/inventory_models.dart';
import '../cubit/inventory_cubit.dart';

/// تعديل الكمية يدويًا: زرّ + وزرّ − حول الكمية الفعلية ثم «حفظ».
/// يرجع true إن تم الحفظ.
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
  /// الكمية المعروضة (تبدأ بالكمية الفعلية وتتغيّر بالـ + والـ −).
  late int _value;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _value = widget.row.onHand;
  }

  /// الفرق عن الكمية الفعلية: هو ما يُحفظ (لا الرقم النهائي)، فلو تغيّرت
  /// الكمية من فاتورة أثناء فتح النافذة يُطبَّق الفرق على الرقم الحالي.
  int get _delta => _value - widget.row.onHand;

  Future<void> _save() async {
    final delta = _delta;
    if (delta == 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<InventoryCubit>().adjustStock(
            itemId: widget.row.itemId,
            delta: delta,
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

  Widget _stepButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceHighest,
          disabledBackgroundColor: AppColors.surfaceHigh,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final delta = _delta;
    final String deltaText;
    final Color deltaColor;
    if (delta == 0) {
      deltaText = 'لم تتغيّر الكمية';
      deltaColor = AppColors.textMuted;
    } else if (delta > 0) {
      deltaText = 'زيادة $delta قطعة';
      deltaColor = AppColors.secondary;
    } else {
      deltaText = 'نقص ${-delta} قطعة';
      deltaColor = AppColors.danger;
    }

    return AppDialog(
      title: 'تعديل مخزون: ${row.name}',
      icon: Icons.edit_note_rounded,
      iconColor: AppColors.accent,
      width: 420,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: (_busy || delta == 0) ? null : _save,
          icon: const Icon(Icons.check_rounded),
          label: const Text('حفظ'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            row.started
                ? 'الكمية الحالية: ${row.onHand} قطعة'
                : 'لم يبدأ تتبّع هذا الصنف بعد (الكمية الحالية 0).',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepButton(
                Icons.add_rounded,
                'زيادة قطعة',
                _busy ? null : () => setState(() => _value++),
              ),
              SizedBox(
                width: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$_value',
                        style: AppTextStyles.price(
                            _value <= 0 ? AppColors.danger : AppColors.secondary, 32),
                      ),
                    ),
                    Text('قطعة', style: AppTextStyles.bodySmall(AppColors.textMuted)),
                  ],
                ),
              ),
              _stepButton(
                Icons.remove_rounded,
                'إنقاص قطعة',
                (_busy || _value <= 0) ? null : () => setState(() => _value--),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceS),
          Text(
            deltaText,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium(deltaColor),
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
