import 'package:flutter/material.dart';

import '../../../../core/domain/value_objects/money_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/money_field.dart';
import '../../domain/entities/inventory_models.dart';
import 'fields.dart';
import 'new_stock_item_dialog.dart';

/// سطر في محرّر الفاتورة (إدخال + اسم الصنف للعرض).
class DraftLine {
  final PurchaseLineInput input;
  final String itemName;
  const DraftLine(this.input, this.itemName);
}

class _ItemOption {
  final int id;
  final String name;
  const _ItemOption(this.id, this.name);
}

/// يضيف أو يعدّل سطرًا في فاتورة المشتريات. يعيد null عند الإلغاء.
Future<DraftLine?> showPurchaseLineDialog(
  BuildContext context, {
  required List<StockRow> rows,
  DraftLine? existing,
}) {
  return showDialog<DraftLine>(
    context: context,
    builder: (_) => _PurchaseLineDialog(rows: rows, existing: existing),
  );
}

class _PurchaseLineDialog extends StatefulWidget {
  final List<StockRow> rows;
  final DraftLine? existing;
  const _PurchaseLineDialog({required this.rows, this.existing});

  @override
  State<_PurchaseLineDialog> createState() => _PurchaseLineDialogState();
}

class _PurchaseLineDialogState extends State<_PurchaseLineDialog> {
  final _qty = TextEditingController();
  final _perPack = TextEditingController();
  final _price = TextEditingController();
  late final List<_ItemOption> _options;
  int? _itemId;
  PurchaseMode _mode = PurchaseMode.pack;
  String? _itemError;
  String? _qtyError;
  String? _perPackError;
  String? _priceError;

  bool get _isPack => _mode == PurchaseMode.pack;

  @override
  void initState() {
    super.initState();
    _options = [for (final r in widget.rows) _ItemOption(r.itemId, r.name)];
    final e = widget.existing;
    if (e != null) {
      _itemId = e.input.itemId;
      _mode = e.input.mode;
      _qty.text = '${e.input.quantity}';
      if (e.input.piecesPerPack != null) _perPack.text = '${e.input.piecesPerPack}';
      _price.text = formatMoney(e.input.price);
      if (!_options.any((o) => o.id == e.input.itemId)) {
        _options.add(_ItemOption(e.input.itemId, e.itemName));
      }
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _perPack.dispose();
    _price.dispose();
    super.dispose();
  }

  PurchaseLineInput? _buildInput() {
    final qty = parseIntField(_qty.text);
    final price = parseMoney(_price.text);
    if (_itemId == null || qty == null || price == null) return null;
    return PurchaseLineInput(
      itemId: _itemId!,
      mode: _mode,
      quantity: qty,
      piecesPerPack: _isPack ? parseIntField(_perPack.text) : null,
      price: price,
    );
  }

  PurchaseLineCalc? _tryCalc() {
    final input = _buildInput();
    if (input == null) return null;
    try {
      return input.calc();
    } catch (_) {
      return null;
    }
  }

  Future<void> _addNewItem() async {
    final created = await showNewStockItemDialog(context);
    if (created == null || !mounted) return;
    setState(() {
      _options.add(_ItemOption(created.id, created.name));
      _itemId = created.id;
      _itemError = null;
    });
  }

  void _submit() {
    final qty = parseIntField(_qty.text);
    final per = parseIntField(_perPack.text);
    final price = parseMoney(_price.text);
    setState(() {
      _itemError = _itemId == null ? 'اختر الصنف' : null;
      _qtyError = (qty == null || qty <= 0)
          ? (_isPack ? 'أدخل عدد الطرود' : 'أدخل عدد القطع')
          : null;
      _perPackError =
          (_isPack && (per == null || per <= 0)) ? 'أدخل عدد القطع' : null;
      _priceError = (price == null || price.amount <= 0) ? 'أدخل السعر' : null;
    });
    if (_itemError != null ||
        _qtyError != null ||
        _perPackError != null ||
        _priceError != null) {
      return;
    }
    final input = _buildInput()!;
    try {
      input.calc();
    } catch (e) {
      setState(() => _priceError = e is ArgumentError ? '${e.message}' : 'قيمة غير صالحة');
      return;
    }
    final name = _options.firstWhere((o) => o.id == _itemId).name;
    Navigator.of(context).pop(DraftLine(input, name));
  }

  String get _priceLabel {
    switch (_mode) {
      case PurchaseMode.pack:
        return 'سعر الطرد';
      case PurchaseMode.pieceUnitPrice:
        return 'سعر القطعة';
      case PurchaseMode.pieceTotalPrice:
        return 'السعر الإجمالي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final calc = _tryCalc();
    return AppDialog(
      title: widget.existing == null ? 'إضافة صنف للفاتورة' : 'تعديل السطر',
      icon: Icons.add_shopping_cart_rounded,
      iconColor: AppColors.secondary,
      width: 520,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(widget.existing == null ? 'إضافة' : 'حفظ'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey(_itemId),
                  initialValue: _itemId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'الصنف',
                    prefixIcon: const Icon(Icons.label_rounded),
                    errorText: _itemError,
                  ),
                  items: [
                    for (final o in _options)
                      DropdownMenuItem<int>(
                        value: o.id,
                        child: Text(o.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _itemId = v),
                ),
              ),
              const SizedBox(width: Dimensions.spaceS),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: _addNewItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('صنف جديد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          Text('طريقة الإدخال', style: AppTextStyles.label()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('بالطرد'),
                selected: _mode == PurchaseMode.pack,
                onSelected: (_) => setState(() => _mode = PurchaseMode.pack),
              ),
              ChoiceChip(
                label: const Text('بالقطعة (سعر القطعة)'),
                selected: _mode == PurchaseMode.pieceUnitPrice,
                onSelected: (_) => setState(() => _mode = PurchaseMode.pieceUnitPrice),
              ),
              ChoiceChip(
                label: const Text('بالقطعة (سعر إجمالي)'),
                selected: _mode == PurchaseMode.pieceTotalPrice,
                onSelected: (_) => setState(() => _mode = PurchaseMode.pieceTotalPrice),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          if (_isPack)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: IntField(
                    controller: _qty,
                    label: 'عدد الطرود',
                    icon: Icons.inventory_2_rounded,
                    errorText: _qtyError,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: Dimensions.spaceS),
                Expanded(
                  child: IntField(
                    controller: _perPack,
                    label: 'عدد القطع بالطرد',
                    icon: Icons.apps_rounded,
                    errorText: _perPackError,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            )
          else
            IntField(
              controller: _qty,
              label: 'عدد القطع',
              icon: Icons.apps_rounded,
              errorText: _qtyError,
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: Dimensions.spaceM),
          MoneyField(
            controller: _price,
            label: _priceLabel,
            errorText: _priceError,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Container(
            padding: const EdgeInsets.all(Dimensions.spaceM),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(Dimensions.radiusM),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _line('إجمالي القطع',
                    calc == null ? '—' : '${groupThousands(calc.totalPieces)} قطعة'),
                const SizedBox(height: 6),
                _line('سعر القطعة',
                    calc == null ? '—' : formatMoneyWithUnit(calc.unitCost)),
                const SizedBox(height: 6),
                _line('إجمالي السطر',
                    calc == null ? '—' : formatMoneyWithUnit(calc.totalCost),
                    bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Row(
        children: [
          Expanded(
              child: Text(label,
                  style: AppTextStyles.bodyMedium(AppColors.textSecondary))),
          Text(
            value,
            style: bold
                ? AppTextStyles.price(AppColors.secondary, 16)
                : AppTextStyles.bodyLarge(),
          ),
        ],
      );
}
