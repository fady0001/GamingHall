import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../menu/domain/entities/menu_category.dart';
import '../../domain/entities/inventory_models.dart';
import '../cubit/inventory_cubit.dart';
import '../widgets/fields.dart';
import '../widgets/purchase_invoice_detail_dialog.dart';
import '../widgets/purchase_invoice_editor.dart';
import '../widgets/stock_adjust_dialog.dart';
import '../widgets/stock_settings_dialog.dart';

/// المخزون والجرد (للمدير فقط): الكميات الحالية، مشتريات البوفيه بالطرد،
/// والجرد اليومي.
class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'المخزون والجرد',
            subtitle: 'الكميات الحالية، فواتير مشتريات البوفيه، والجرد اليومي',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM),
            child: TabBar(
              onTap: (i) {
                if (i == 2) context.read<InventoryCubit>().refreshCountDate();
              },
              tabs: const [
                Tab(icon: Icon(Icons.inventory_2_rounded), text: 'المخزون'),
                Tab(icon: Icon(Icons.shopping_cart_checkout_rounded), text: 'المشتريات'),
                Tab(icon: Icon(Icons.fact_check_rounded), text: 'الجرد اليومي'),
                Tab(icon: Icon(Icons.history_rounded), text: 'سجل التعديلات'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _StockTab(),
                _PurchasesTab(),
                _CountTab(),
                _AdjustmentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── تبويب المخزون ─────────────────────────

class _StockTab extends StatelessWidget {
  const _StockTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryCubit>().state;
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    if (state.rows.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_rounded,
        title: 'لا توجد أصناف',
        message: 'أضف الأصناف من "قائمة المشتريات" أولًا، ثم سجّل مشترياتها هنا.',
      );
    }

    final attention = state.attention;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Dimensions.spaceL, Dimensions.spaceM, Dimensions.spaceL, Dimensions.spaceL),
      children: [
        Wrap(
          spacing: Dimensions.spaceS,
          runSpacing: Dimensions.spaceS,
          children: [
            _SummaryCard(
              icon: Icons.inventory_2_rounded,
              label: 'أصناف مُتتبَّعة',
              value: '${state.tracked.length}',
              color: AppColors.secondary,
            ),
            _SummaryCard(
              icon: Icons.warning_amber_rounded,
              label: 'تحتاج انتباه',
              value: '${attention.length}',
              color: attention.isEmpty ? AppColors.success : AppColors.warning,
            ),
            _SummaryCard(
              icon: Icons.payments_outlined,
              label: 'قيمة المخزون (بالتكلفة)',
              value: formatMoneyWithUnit(state.totalValue),
              color: AppColors.primaryLight,
            ),
          ],
        ),
        if (attention.isNotEmpty) ...[
          const SizedBox(height: Dimensions.spaceM),
          AppCard(
            accentColor: AppColors.warning,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                const SizedBox(width: Dimensions.spaceS),
                Expanded(
                  child: Text(
                    'نفد أو قارب على النفاد: ${attention.map((r) => r.name).join('، ')}',
                    style: AppTextStyles.bodyMedium(),
                  ),
                ),
              ],
            ),
          ),
        ],
        for (final c in MenuCategory.values)
          ..._section(context, c, state.rows.where((r) => r.category == c).toList()),
      ],
    );
  }

  List<Widget> _section(BuildContext context, MenuCategory c, List<StockRow> rows) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: Dimensions.spaceM, bottom: Dimensions.spaceS),
        child: Row(
          children: [
            Icon(c.icon, size: 20, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('${c.label} (${rows.length})', style: AppTextStyles.heading3()),
          ],
        ),
      ),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
          child: _StockRowCard(row: r),
        ),
    ];
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: AppCard(
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Dimensions.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value, style: AppTextStyles.price(color, 18)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockRowCard extends StatelessWidget {
  final StockRow row;
  const _StockRowCard({required this.row});

  Widget _badge() {
    if (!row.trackStock) {
      return StatusBadge(
          label: 'غير مُتتبَّع', color: AppColors.textMuted, icon: Icons.block_rounded);
    }
    if (!row.started) {
      return StatusBadge(
          label: 'لم يبدأ', color: AppColors.info, icon: Icons.hourglass_empty_rounded);
    }
    if (row.isOut) {
      return StatusBadge(
          label: 'نفد', color: AppColors.danger, icon: Icons.remove_shopping_cart_rounded);
    }
    if (row.isLow) {
      return StatusBadge(
          label: 'منخفض', color: AppColors.warning, icon: Icons.warning_amber_rounded);
    }
    return StatusBadge(
        label: 'متوفر', color: AppColors.success, icon: Icons.check_circle_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final showQty = row.trackStock && row.started;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 8),
      accentColor: row.needsAttention ? (row.isOut ? AppColors.danger : AppColors.warning) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: AppTextStyles.bodyLarge()),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _badge(),
                    if (!row.isSellable)
                      StatusBadge(
                          label: 'لا يُباع',
                          color: AppColors.textMuted,
                          icon: Icons.visibility_off_rounded),
                    if (row.trackStock && row.unitCost.amount > 0)
                      Text('تكلفة القطعة ${formatMoneyWithUnit(row.unitCost)}',
                          style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          if (showQty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceS),
              child: Column(
                children: [
                  Text('${row.onHand}',
                      style: AppTextStyles.price(
                          row.isOut ? AppColors.danger : AppColors.secondary, 22)),
                  Text('قطعة', style: AppTextStyles.bodySmall(AppColors.textMuted)),
                ],
              ),
            ),
          IconButton(
            tooltip: 'تعديل الكمية يدويًا',
            onPressed: row.trackStock ? () => showStockAdjustDialog(context, row) : null,
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(
            tooltip: 'إعدادات الصنف',
            onPressed: () => showStockSettingsDialog(context, row),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── تبويب المشتريات (فواتير) ─────────────────────────

class _PurchasesTab extends StatelessWidget {
  const _PurchasesTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryCubit>().state;
    final remaining = state.totalRemaining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Dimensions.spaceL, Dimensions.spaceM, Dimensions.spaceL, Dimensions.spaceS),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('فواتير المشتريات (الأحدث أولًا)', style: AppTextStyles.heading3()),
                    if (remaining.amount > 0)
                      Text('غير مدفوع للموردين: ${formatMoneyWithUnit(remaining)}',
                          style: AppTextStyles.bodySmall(AppColors.warning)),
                  ],
                ),
              ),
              SizedBox(
                height: Dimensions.buttonHeight,
                child: FilledButton.icon(
                  onPressed: state.isLoading
                      ? null
                      : () => showPurchaseInvoiceEditor(context, rows: state.rows),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('فاتورة مشتريات'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.invoices.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'لا توجد فواتير مشتريات بعد',
                  message:
                      'سجّل كل شراء كفاتورة، وضمنها عدة أصناف بالطرد أو بالقطعة، وحدّد إن كانت مدفوعة أو بقي عليها مبلغ. يزيد المخزون وتُحسب تكلفة القطعة تلقائيًا.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      Dimensions.spaceL, 0, Dimensions.spaceL, Dimensions.spaceL),
                  children: [
                    for (final inv in state.invoices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
                        child: _InvoiceCard(invoice: inv),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final PurchaseInvoice invoice;
  const _InvoiceCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final names = inv.lines.map((l) => l.itemName).join('، ');
    final meta = [
      formatDate(inv.purchasedAt),
      if (inv.supplier != null && inv.supplier!.isNotEmpty) inv.supplier!,
      if (inv.invoiceNo != null && inv.invoiceNo!.isNotEmpty) 'رقم ${inv.invoiceNo}',
    ].join('  •  ');

    return AppCard(
      onTap: () => showPurchaseInvoiceDetail(context, inv.id),
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta, style: AppTextStyles.bodyLarge()),
                const SizedBox(height: 2),
                Text(
                  '${inv.lines.length} صنف: $names',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall(AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                paymentStatusBadge(inv),
              ],
            ),
          ),
          const SizedBox(width: Dimensions.spaceS),
          Text(formatMoneyWithUnit(inv.payable),
              style: AppTextStyles.price(AppColors.secondary, 16)),
          const Icon(Icons.chevron_left_rounded),
        ],
      ),
    );
  }
}

// ───────────────────────── تبويب الجرد اليومي ─────────────────────────

class _CountTab extends StatefulWidget {
  const _CountTab();

  @override
  State<_CountTab> createState() => _CountTabState();
}

class _CountTabState extends State<_CountTab> {
  final Map<int, TextEditingController> _controllers = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// يُنشئ حقل الصنف عند أول ظهور، ويملؤه بجرد اليوم المحفوظ إن وُجد.
  TextEditingController _controllerFor(StockRow row, InventoryState state) {
    return _controllers.putIfAbsent(row.itemId, () {
      final saved = state.countFor(row.itemId);
      return TextEditingController(text: saved == null ? '' : '${saved.counted}');
    });
  }

  /// جرد وصل بعد بناء الحقول (من البث): نملأ الحقول الفارغة فقط.
  void _fillFromSaved(InventoryState state) {
    for (final rec in state.todayCounts) {
      final c = _controllers[rec.itemId];
      if (c != null && c.text.isEmpty) c.text = '${rec.counted}';
    }
  }

  Future<void> _save(InventoryState state) async {
    final entries = <CountEntry>[];
    for (final row in state.tracked) {
      final text = _controllers[row.itemId]?.text ?? '';
      final value = parseIntField(text);
      if (value == null) continue;
      final saved = state.countFor(row.itemId);
      if (saved != null && saved.counted == value) continue; // لم يتغيّر
      entries.add(CountEntry(row.itemId, value));
    }
    if (entries.isEmpty) {
      showAppSnack(context, 'لم تُدخل أي رقم جديد للجرد', error: true);
      return;
    }

    // فحص قبل الحفظ: أصناف الفعلي فيها أكبر من المتوقع (احتمال شراء غير مسجّل).
    final surplus = <String>[];
    for (final e in entries) {
      final row = state.tracked.firstWhere((r) => r.itemId == e.itemId);
      if (!row.started) continue; // أول جرد للصنف يحدد الكمية الابتدائية
      final expected = state.countFor(e.itemId)?.expected ?? row.onHand;
      if (e.counted > expected) surplus.add('${row.name} (+${e.counted - expected})');
    }

    final choice = await showDialog<_CountChoice>(
      context: context,
      builder: (_) => _CountCheckDialog(
        itemCount: entries.length,
        invoicesToday: state.invoicesTodayCount,
        surplus: surplus,
      ),
    );
    if (!mounted) return;
    if (choice == _CountChoice.goPurchases) {
      DefaultTabController.of(context).animateTo(1);
      return;
    }
    if (choice != _CountChoice.save) return;

    setState(() => _busy = true);
    try {
      final n = await context.read<InventoryCubit>().saveCounts(entries);
      if (mounted) showAppSnack(context, 'تم حفظ جرد $n صنف');
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InventoryCubit, InventoryState>(
      listenWhen: (a, b) => a.todayCounts != b.todayCounts,
      listener: (context, state) => _fillFromSaved(state),
      builder: (context, state) {
        if (state.isLoading) return const Center(child: CircularProgressIndicator());
        final rows = state.tracked;
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.fact_check_rounded,
            title: 'لا توجد أصناف للجرد',
            message: 'فعّل تتبّع المخزون لصنف واحد على الأقل من تبويب "المخزون".',
          );
        }
        final done = rows.where((r) => state.countFor(r.itemId) != null).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Dimensions.spaceL, Dimensions.spaceM, Dimensions.spaceL, Dimensions.spaceS),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('جرد ${state.countDate}', style: AppTextStyles.heading3()),
                        Text('تم جرد $done من ${rows.length} صنف',
                            style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: Dimensions.buttonHeight,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _save(state),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('حفظ الجرد'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceL),
              child: Text(
                'اكتب الكمية الفعلية الموجودة. الأصناف التي تتركها فارغة لا تتغيّر.',
                style: AppTextStyles.bodySmall(AppColors.textMuted),
              ),
            ),
            const SizedBox(height: Dimensions.spaceS),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Dimensions.spaceL, 0, Dimensions.spaceL, Dimensions.spaceL),
                children: [
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
                      child: _countRow(row, state),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _countRow(StockRow row, InventoryState state) {
    final controller = _controllerFor(row, state);
    final saved = state.countFor(row.itemId);
    final expected = saved?.expected ?? row.onHand;
    final typed = parseIntField(controller.text);
    final diff = typed == null ? null : typed - expected;

    Widget? diffBadge;
    if (diff != null) {
      if (diff == 0) {
        diffBadge = StatusBadge(
            label: 'مطابق', color: AppColors.success, icon: Icons.check_circle_outline_rounded);
      } else if (diff < 0) {
        diffBadge = StatusBadge(
            label: 'نقص ${-diff}', color: AppColors.danger, icon: Icons.trending_down_rounded);
      } else {
        diffBadge = StatusBadge(
            label: 'زيادة $diff', color: AppColors.warning, icon: Icons.trending_up_rounded);
      }
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: AppTextStyles.bodyLarge()),
                const SizedBox(height: 2),
                Text(
                  row.started ? 'المتوقع: $expected' : 'المتوقع: — (أول جرد يحدد الكمية)',
                  style: AppTextStyles.bodySmall(AppColors.textSecondary),
                ),
                if (saved != null)
                  Text('تم الجرد ${formatClock(saved.countedAt)}',
                      style: AppTextStyles.bodySmall(AppColors.textMuted)),
              ],
            ),
          ),
          if (diffBadge != null) ...[
            diffBadge,
            const SizedBox(width: Dimensions.spaceS),
          ],
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]'))],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'الفعلي', isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CountChoice { save, goPurchases }

/// سؤال التأكيد قبل حفظ الجرد: هل سُجّلت كل المشتريات؟
class _CountCheckDialog extends StatelessWidget {
  final int itemCount;
  final int invoicesToday;
  final List<String> surplus;
  const _CountCheckDialog({
    required this.itemCount,
    required this.invoicesToday,
    required this.surplus,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'قبل حفظ الجرد',
      icon: Icons.fact_check_rounded,
      iconColor: surplus.isEmpty ? AppColors.primaryLight : AppColors.warning,
      width: 500,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(_CountChoice.goPurchases),
          icon: const Icon(Icons.shopping_cart_checkout_rounded),
          label: const Text('لأ، سجّل شراء أولًا'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_CountChoice.save),
          icon: const Icon(Icons.save_rounded),
          label: const Text('نعم، احفظ الجرد'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('هل سجّلت كل مشتريات اليوم؟', style: AppTextStyles.heading3()),
          const SizedBox(height: Dimensions.spaceS),
          Text(
            invoicesToday == 0
                ? 'لم تسجّل أي فاتورة مشتريات اليوم.'
                : 'سجّلت اليوم $invoicesToday فاتورة مشتريات.',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          if (surplus.isNotEmpty) ...[
            const SizedBox(height: Dimensions.spaceM),
            AppCard(
              accentColor: AppColors.warning,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  const SizedBox(width: Dimensions.spaceS),
                  Expanded(
                    child: Text(
                      'الكمية الفعلية أكبر من المتوقع في: ${surplus.join('، ')}. '
                      'قد يكون هناك شراء لم يُسجَّل.',
                      style: AppTextStyles.bodyMedium(),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Dimensions.spaceM),
          Text(
            'سيُسوّى مخزون $itemCount صنف على الأرقام التي أدخلتها، وتُسجَّل الفروقات.',
            style: AppTextStyles.bodySmall(AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── تبويب سجل التعديلات ─────────────────────────

class _AdjustmentsTab extends StatelessWidget {
  const _AdjustmentsTab();

  @override
  Widget build(BuildContext context) {
    final list = context.watch<InventoryCubit>().state.adjustments;
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'لا توجد تعديلات يدوية',
        message: 'عند تعديل كمية صنف يدويًا من تبويب "المخزون" يُسجَّل التعديل وسببه هنا.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Dimensions.spaceL),
      children: [
        for (final a in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.itemName, style: AppTextStyles.bodyLarge()),
                        Text(a.reason,
                            style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
                        Text(formatDateTime(a.createdAt),
                            style: AppTextStyles.bodySmall(AppColors.textMuted)),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: a.qty > 0 ? 'زيادة ${a.qty}' : 'نقص ${-a.qty}',
                    color: a.qty > 0 ? AppColors.success : AppColors.danger,
                    icon: a.qty > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
