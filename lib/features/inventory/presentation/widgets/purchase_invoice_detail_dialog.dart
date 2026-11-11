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
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities/inventory_models.dart';
import '../cubit/inventory_cubit.dart';
import 'purchase_invoice_editor.dart';

/// شارة حالة الدفع (تُستعمل في القائمة والتفاصيل).
Widget paymentStatusBadge(PurchaseInvoice inv) {
  switch (inv.status) {
    case PaymentStatus.paid:
      return StatusBadge(
          label: 'مدفوعة', color: AppColors.success, icon: Icons.check_circle_outline_rounded);
    case PaymentStatus.partial:
      return StatusBadge(
          label: 'متبقي ${formatMoneyWithUnit(inv.remaining)}',
          color: AppColors.warning,
          icon: Icons.timelapse_rounded);
    case PaymentStatus.unpaid:
      return StatusBadge(
          label: 'غير مدفوعة', color: AppColors.danger, icon: Icons.error_outline_rounded);
  }
}

Future<void> showPurchaseInvoiceDetail(BuildContext context, int invoiceId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InvoiceDetailDialog(invoiceId: invoiceId),
  );
}

class _InvoiceDetailDialog extends StatelessWidget {
  final int invoiceId;
  const _InvoiceDetailDialog({required this.invoiceId});

  Future<void> _delete(BuildContext context, PurchaseInvoice inv) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف الفاتورة كاملة؟',
      message:
          'سيُسحب كل ما دخل من هذه الفاتورة من المخزون وتُحذف دفعاتها. استخدمها لتصحيح خطأ فقط.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<InventoryCubit>().deleteInvoice(inv.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _edit(BuildContext context, PurchaseInvoice inv) async {
    final rows = context.read<InventoryCubit>().state.rows;
    final navigator = Navigator.of(context);
    navigator.pop(); // نغلق التفاصيل ثم نفتح المحرّر
    await showPurchaseInvoiceEditor(navigator.context, rows: rows, existing: inv);
  }

  Future<void> _deletePayment(BuildContext context, PurchasePayment p) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف الدفعة؟',
      message: 'ستُحذف دفعة ${formatMoneyWithUnit(p.amount)} ويزيد المتبقي على الفاتورة.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<InventoryCubit>().deletePayment(p.id);
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.select<InventoryCubit, PurchaseInvoice?>((c) {
      for (final i in c.state.invoices) {
        if (i.id == invoiceId) return i;
      }
      return null;
    });
    if (inv == null) {
      // حُذفت الفاتورة: نغلق النافذة.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final title = [
      'فاتورة ${formatDate(inv.purchasedAt)}',
      if (inv.supplier != null && inv.supplier!.isNotEmpty) inv.supplier!,
    ].join(' • ');

    return AppDialog(
      title: title,
      icon: Icons.receipt_long_rounded,
      iconColor: AppColors.secondary,
      width: 680,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
        OutlinedButton.icon(
          onPressed: () => _delete(context, inv),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('حذف الفاتورة'),
        ),
        OutlinedButton.icon(
          onPressed: () => _edit(context, inv),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('تعديل'),
        ),
        if (inv.remaining.amount > 0)
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _PaymentDialog(invoice: inv),
            ),
            icon: const Icon(Icons.payments_rounded),
            label: const Text('تسديد دفعة'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Dimensions.spaceS,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              paymentStatusBadge(inv),
              if (inv.invoiceNo != null && inv.invoiceNo!.isNotEmpty)
                Text('رقم ${inv.invoiceNo}',
                    style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
            ],
          ),
          if (inv.note != null && inv.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(inv.note!, style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
          ],
          const SizedBox(height: Dimensions.spaceM),
          Text('الأصناف', style: AppTextStyles.heading3()),
          const SizedBox(height: Dimensions.spaceS),
          for (final l in inv.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Dimensions.spaceS, vertical: 8),
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
                          Text(
                            '${l.quantityText}  •  سعر القطعة ${formatMoneyWithUnit(l.unitCost)}',
                            style: AppTextStyles.bodySmall(AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(formatMoneyWithUnit(l.totalCost),
                        style: AppTextStyles.price(AppColors.secondary, 15)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Dimensions.spaceS),
          _totalRow('مجموع الأصناف', formatMoneyWithUnit(inv.itemsTotal)),
          if (inv.discount.amount > 0)
            _totalRow('الخصم', '- ${formatMoneyWithUnit(inv.discount)}'),
          _totalRow('المطلوب دفعه', formatMoneyWithUnit(inv.payable), bold: true),
          _totalRow('المدفوع', formatMoneyWithUnit(inv.paid)),
          _totalRow(
            'المتبقي',
            formatMoneyWithUnit(inv.remaining.amount < 0 ? Money.zero : inv.remaining),
            bold: true,
          ),
          const SizedBox(height: Dimensions.spaceM),
          Text('الدفعات', style: AppTextStyles.heading3()),
          const SizedBox(height: Dimensions.spaceS),
          if (inv.payments.isEmpty)
            Text('لا توجد دفعات مسجّلة.',
                style: AppTextStyles.bodyMedium(AppColors.textSecondary))
          else
            for (final p in inv.payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatDate(p.paidAt) +
                            ((p.note == null || p.note!.isEmpty) ? '' : '  •  ${p.note}'),
                        style: AppTextStyles.bodyMedium(AppColors.textSecondary),
                      ),
                    ),
                    Text(formatMoneyWithUnit(p.amount), style: AppTextStyles.bodyLarge()),
                    IconButton(
                      tooltip: 'حذف الدفعة',
                      onPressed: () => _deletePayment(context, p),
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: AppTextStyles.bodyMedium(AppColors.textSecondary))),
            Text(value,
                style: bold
                    ? AppTextStyles.price(AppColors.secondary, 16)
                    : AppTextStyles.bodyLarge()),
          ],
        ),
      );
}

class _PaymentDialog extends StatefulWidget {
  final PurchaseInvoice invoice;
  const _PaymentDialog({required this.invoice});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  String? _amountError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: formatMoney(widget.invoice.remaining));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parseMoney(_amount.text);
    setState(() {
      _error = null;
      _amountError = (amount == null || amount.amount <= 0) ? 'أدخل المبلغ' : null;
    });
    if (amount == null || amount.amount <= 0) return;

    setState(() => _busy = true);
    try {
      await context.read<InventoryCubit>().addPayment(
            invoiceId: widget.invoice.id,
            amount: amount,
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop();
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
      title: 'تسديد دفعة',
      icon: Icons.payments_rounded,
      iconColor: AppColors.success,
      width: 440,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('تسجيل الدفعة'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('المتبقي على الفاتورة: ${formatMoneyWithUnit(widget.invoice.remaining)}',
              style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
          const SizedBox(height: Dimensions.spaceM),
          MoneyField(
            controller: _amount,
            label: 'مبلغ الدفعة',
            errorText: _amountError,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _note,
            enabled: !_busy,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'ملاحظة (اختياري)',
              prefixIcon: Icon(Icons.notes_rounded),
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
