import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/money_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/money_field.dart';
import '../../domain/entities/inventory_models.dart';
import '../cubit/inventory_cubit.dart';
import 'purchase_line_dialog.dart';

/// إنشاء فاتورة مشتريات جديدة، أو تعديل [existing]. يعيد true عند الحفظ.
Future<bool> showPurchaseInvoiceEditor(
  BuildContext context, {
  required List<StockRow> rows,
  PurchaseInvoice? existing,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _InvoiceEditor(rows: rows, existing: existing),
  );
  return ok ?? false;
}

enum _PayChoice { full, none, partial }

class _InvoiceEditor extends StatefulWidget {
  final List<StockRow> rows;
  final PurchaseInvoice? existing;
  const _InvoiceEditor({required this.rows, this.existing});

  @override
  State<_InvoiceEditor> createState() => _InvoiceEditorState();
}

class _InvoiceEditorState extends State<_InvoiceEditor> {
  final _supplier = TextEditingController();
  final _invoiceNo = TextEditingController();
  final _note = TextEditingController();
  final _discount = TextEditingController();
  final _paidPartial = TextEditingController();
  final List<DraftLine> _lines = [];
  late DateTime _date;
  _PayChoice _pay = _PayChoice.full;
  String? _paidError;
  String? _discountError;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.purchasedAt ?? DateTime.now();
    if (e != null) {
      _supplier.text = e.supplier ?? '';
      _invoiceNo.text = e.invoiceNo ?? '';
      _note.text = e.note ?? '';
      if (e.discount.amount > 0) _discount.text = formatMoney(e.discount);
      for (final l in e.lines) {
        _lines.add(DraftLine(l.toInput(), l.itemName));
      }
    }
  }

  @override
  void dispose() {
    _supplier.dispose();
    _invoiceNo.dispose();
    _note.dispose();
    _discount.dispose();
    _paidPartial.dispose();
    super.dispose();
  }

  Money get _itemsTotal {
    var t = 0;
    for (final l in _lines) {
      try {
        t += l.input.calc().totalCost.amount;
      } catch (_) {}
    }
    return Money(t);
  }

  Money get _discountValue => parseMoney(_discount.text) ?? Money.zero;
  Money get _payable => _itemsTotal - _discountValue;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked == null) return;
    // نحتفظ بالساعة حتى يبقى ترتيب فواتير اليوم الواحد منطقيًا.
    setState(() => _date =
        DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
  }

  Future<void> _addLine() async {
    final line = await showPurchaseLineDialog(context, rows: widget.rows);
    if (line != null && mounted) setState(() => _lines.add(line));
  }

  Future<void> _editLine(int index) async {
    final line = await showPurchaseLineDialog(context,
        rows: widget.rows, existing: _lines[index]);
    if (line != null && mounted) setState(() => _lines[index] = line);
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _paidError = null;
      _discountError = null;
    });
    if (_lines.isEmpty) {
      setState(() => _error = 'أضف صنفًا واحدًا على الأقل للفاتورة');
      return;
    }
    if (_discountValue > _itemsTotal) {
      setState(() => _discountError = 'الخصم أكبر من مجموع الفاتورة');
      return;
    }

    var paid = Money.zero;
    if (!_isEdit) {
      switch (_pay) {
        case _PayChoice.full:
          paid = _payable;
        case _PayChoice.none:
          paid = Money.zero;
        case _PayChoice.partial:
          final p = parseMoney(_paidPartial.text);
          if (p == null || p.amount <= 0) {
            setState(() => _paidError = 'أدخل المبلغ المدفوع');
            return;
          }
          if (p > _payable) {
            setState(() => _paidError = 'المدفوع أكبر من قيمة الفاتورة');
            return;
          }
          paid = p;
      }
    }

    setState(() => _busy = true);
    try {
      await context.read<InventoryCubit>().saveInvoice(PurchaseInvoiceInput(
            id: widget.existing?.id,
            purchasedAt: _date,
            supplier: _supplier.text,
            invoiceNo: _invoiceNo.text,
            note: _note.text,
            discount: _discountValue,
            lines: [for (final l in _lines) l.input],
            initialPaid: paid,
          ));
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
      title: _isEdit ? 'تعديل فاتورة مشتريات' : 'فاتورة مشتريات جديدة',
      icon: Icons.receipt_long_rounded,
      iconColor: AppColors.secondary,
      width: 720,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(_isEdit ? 'حفظ التعديل' : 'حفظ الفاتورة'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Dimensions.spaceS,
            runSpacing: Dimensions.spaceS,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _supplier,
                  enabled: !_busy,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'اسم المورّد (اختياري)',
                    prefixIcon: Icon(Icons.storefront_rounded),
                    counterText: '',
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _invoiceNo,
                  enabled: !_busy,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'رقم الفاتورة (اختياري)',
                    prefixIcon: Icon(Icons.tag_rounded),
                    counterText: '',
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(formatDate(_date)),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _note,
            enabled: !_busy,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياري)',
              prefixIcon: Icon(Icons.notes_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Row(
            children: [
              Expanded(child: Text('الأصناف (${_lines.length})', style: AppTextStyles.heading3())),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _addLine,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة صنف'),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceS),
          if (_lines.isEmpty)
            Container(
              padding: const EdgeInsets.all(Dimensions.spaceM),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(Dimensions.radiusM),
              ),
              child: Text('لم تُضف أصنافًا بعد.',
                  style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
            )
          else
            for (var i = 0; i < _lines.length; i++) _lineTile(i),
          const SizedBox(height: Dimensions.spaceM),
          MoneyField(
            controller: _discount,
            label: 'خصم على الفاتورة (اختياري)',
            errorText: _discountError,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Dimensions.spaceM),
          if (!_isEdit) ...[
            Text('الدفع', style: AppTextStyles.label()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('مدفوعة بالكامل'),
                  selected: _pay == _PayChoice.full,
                  onSelected: _busy ? null : (_) => setState(() => _pay = _PayChoice.full),
                ),
                ChoiceChip(
                  label: const Text('غير مدفوعة'),
                  selected: _pay == _PayChoice.none,
                  onSelected: _busy ? null : (_) => setState(() => _pay = _PayChoice.none),
                ),
                ChoiceChip(
                  label: const Text('دفع جزئي'),
                  selected: _pay == _PayChoice.partial,
                  onSelected: _busy ? null : (_) => setState(() => _pay = _PayChoice.partial),
                ),
              ],
            ),
            if (_pay == _PayChoice.partial) ...[
              const SizedBox(height: Dimensions.spaceS),
              MoneyField(
                controller: _paidPartial,
                label: 'المبلغ المدفوع',
                errorText: _paidError,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ] else
            Text(
              'الدفعات تُدار من تفاصيل الفاتورة (تسديد دفعة / حذف دفعة).',
              style: AppTextStyles.bodySmall(AppColors.textMuted),
            ),
          const SizedBox(height: Dimensions.spaceM),
          _summary(),
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceM),
            Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _lineTile(int i) {
    final l = _lines[i];
    PurchaseLineCalc? c;
    try {
      c = l.input.calc();
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceS, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(Dimensions.radiusM),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.itemName, style: AppTextStyles.bodyLarge()),
                  if (c != null)
                    Text(
                      c.entryMode == 'pack'
                          ? '${c.packs} طرد × ${c.piecesPerPack} قطعة = ${c.totalPieces} قطعة  •  سعر القطعة ${formatMoneyWithUnit(c.unitCost)}'
                          : '${c.totalPieces} قطعة  •  سعر القطعة ${formatMoneyWithUnit(c.unitCost)}',
                      style: AppTextStyles.bodySmall(AppColors.textSecondary),
                    ),
                ],
              ),
            ),
            if (c != null)
              Text(formatMoneyWithUnit(c.totalCost),
                  style: AppTextStyles.price(AppColors.secondary, 15)),
            IconButton(
              tooltip: 'تعديل',
              onPressed: _busy ? null : () => _editLine(i),
              icon: const Icon(Icons.edit_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'حذف السطر',
              onPressed: _busy ? null : () => setState(() => _lines.removeAt(i)),
              icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: AppTextStyles.bodyMedium(AppColors.textSecondary))),
              Text(value,
                  style: bold
                      ? AppTextStyles.price(AppColors.secondary, 17)
                      : AppTextStyles.bodyLarge()),
            ],
          ),
        );

    final discount = _discountValue;
    return Container(
      padding: const EdgeInsets.all(Dimensions.spaceM),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
      ),
      child: Column(
        children: [
          row('مجموع الأصناف', formatMoneyWithUnit(_itemsTotal)),
          if (discount.amount > 0) row('الخصم', '- ${formatMoneyWithUnit(discount)}'),
          row('المطلوب دفعه', formatMoneyWithUnit(_payable.amount < 0 ? Money.zero : _payable),
              bold: true),
        ],
      ),
    );
  }
}
