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
import '../../domain/entities/inventory_models.dart';
import '../cubit/inventory_cubit.dart';
import 'fields.dart';

Future<bool> showStockSettingsDialog(BuildContext context, StockRow row) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _StockSettingsDialog(row: row),
  );
  return ok ?? false;
}

class _StockSettingsDialog extends StatefulWidget {
  final StockRow row;
  const _StockSettingsDialog({required this.row});

  @override
  State<_StockSettingsDialog> createState() => _StockSettingsDialogState();
}

class _StockSettingsDialogState extends State<_StockSettingsDialog> {
  late final TextEditingController _min;
  late final TextEditingController _price;
  late bool _track;
  late bool _sellable;
  String? _priceError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _track = widget.row.trackStock;
    _sellable = widget.row.isSellable;
    _min = TextEditingController(text: widget.row.minStock.toString());
    _price = TextEditingController(
        text: widget.row.price.amount > 0 ? formatMoney(widget.row.price) : '');
  }

  @override
  void dispose() {
    _min.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final min = parseIntField(_min.text) ?? 0;
    final price = parseMoney(_price.text);
    setState(() {
      _error = null;
      _priceError =
          (_sellable && (price == null || price.amount <= 0)) ? 'أدخل سعر البيع' : null;
    });
    if (_priceError != null) return;

    setState(() => _busy = true);
    try {
      await context.read<InventoryCubit>().updateStockSettings(
            itemId: widget.row.itemId,
            trackStock: _track,
            minStock: min,
            isSellable: _sellable,
            price: price,
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
    return AppDialog(
      title: widget.row.name,
      icon: Icons.tune_rounded,
      iconColor: AppColors.accent,
      width: 460,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('حفظ'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('يُباع للزبائن'),
            subtitle: Text(
              'عند التفعيل يظهر الصنف في قائمة المشتريات وفي الفواتير بسعر البيع.',
              style: AppTextStyles.bodySmall(AppColors.textSecondary),
            ),
            value: _sellable,
            onChanged: _busy ? null : (v) => setState(() => _sellable = v),
          ),
          if (_sellable) ...[
            const SizedBox(height: Dimensions.spaceS),
            MoneyField(
              controller: _price,
              label: 'سعر البيع',
              errorText: _priceError,
              enabled: !_busy,
            ),
          ],
          const Divider(height: Dimensions.spaceL),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تتبّع مخزون هذا الصنف'),
            subtitle: Text(
              'أوقفه للخدمات التي لا تُخزَّن (مثل الأركيلة والثلج).',
              style: AppTextStyles.bodySmall(AppColors.textSecondary),
            ),
            value: _track,
            onChanged: _busy ? null : (v) => setState(() => _track = v),
          ),
          const SizedBox(height: Dimensions.spaceS),
          IntField(
            controller: _min,
            label: 'حدّ التنبيه (عدد القطع)',
            icon: Icons.notifications_active_rounded,
            enabled: !_busy && _track,
          ),
          const SizedBox(height: 6),
          Text(
            'عندما تنزل الكمية إلى هذا الرقم أو أقل يظهر تحذير. التحذير لا يمنع البيع.',
            style: AppTextStyles.bodySmall(AppColors.textMuted),
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
