import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/live_builder.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../printing/data/invoice_pdf_builder.dart';
import '../../../printing/data/invoice_printer.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../domain/entities/invoice.dart';
import '../cubit/invoices_cubit.dart';
import '../widgets/invoice_summary_card.dart';
import '../widgets/item_line_tile.dart';
import '../widgets/menu_picker_panel.dart';
import '../widgets/play_line_tile.dart';
import '../widgets/start_play_dialog.dart';

/// صفحة الفاتورة: للمفتوحة (إضافة لعب/أصناف، إيقاف، محاسبة) وللمغلقة (عرض
/// فقط مع طباعة وحفظ PDF).
class InvoiceDetailPage extends StatefulWidget {
  final int invoiceId;
  const InvoiceDetailPage({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late final Stream<Invoice?> _stream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stream = context.read<InvoicesCubit>().watchById(widget.invoiceId);
  }

  Future<void> _checkout(Invoice invoice, AppSettings settings) async {
    final totals = invoice.totalsAt(DateTime.now(), settings.billingPolicy);
    final running = invoice.runningLines;

    final ok = await showConfirmDialog(
      context,
      title: 'محاسبة الفاتورة؟',
      message:
          'الإجمالي ${formatMoneyWithUnit(totals.finalTotal)}.'
          '${running.isEmpty ? '' : '\nسيتوقف الوقت الآن على: ${running.map((l) => l.resourceName).join('، ')}.'}'
          '\nبعد المحاسبة لا يمكن تعديل الفاتورة.',
      confirmLabel: 'محاسبة وإغلاق',
      icon: Icons.point_of_sale_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final closed = await context.read<InvoicesCubit>().checkout(invoice.id);
      if (!mounted) return;
      showAppSnack(
        context,
        'تمت المحاسبة: ${formatMoneyWithUnit(closed.settledTotals!.finalTotal)}',
      );
      if (settings.autoPrint) {
        final error = await InvoicePrinter.printDirect(closed, settings);
        if (mounted && error != null) {
          showAppSnack(context, error, error: true);
        }
      }
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEmpty(Invoice invoice) async {
    final ok = await showConfirmDialog(
      context,
      title: 'حذف الفاتورة؟',
      message: 'الفاتورة فارغة (لا لعب ولا طلبات). سيتم حذفها نهائيًا.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<InvoicesCubit>().deleteIfEmpty(invoice.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _print(Invoice invoice, AppSettings settings) async {
    setState(() => _busy = true);
    final error = await InvoicePrinter.printDirect(invoice, settings);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      showAppSnack(context, 'أُرسلت الفاتورة إلى الطابعة');
    } else {
      showAppSnack(context, error, error: true);
    }
  }

  Future<void> _savePdf(Invoice invoice, AppSettings settings) async {
    try {
      final path = await InvoicePrinter.savePdf(invoice, settings);
      if (!mounted) return;
      showAppSnack(
        context,
        'تم حفظ الفاتورة: $path',
        action: SnackBarAction(
          label: 'إظهار الملف',
          onPressed: () => InvoicePrinter.revealInExplorer(path),
        ),
      );
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذّر حفظ الملف: $e', error: true);
    }
  }

  Future<void> _preview(Invoice invoice, AppSettings settings) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 460,
          height: 700,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'معاينة الفاتورة',
                        style: AppTextStyles.heading3(),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) =>
                      InvoicePdfBuilder.build(invoice, settings, format),
                  initialPageFormat: InvoicePrinter.format,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'invoice-${invoice.id}.pdf',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Invoice invoice, AppSettings settings) {
    return LayoutBuilder(
      builder: (context, c) {
        // شاشة عريضة وطويلة: الأسطر يسارًا ولوحة جانبية يمينًا. غير ذلك (نافذة
        // ضيقة أو قصيرة): تخطيط عمودي كله قابل للتمرير حتى لا يحدث overflow.
        final stacked = context.isCompact || c.maxHeight < 600;
        if (stacked) return _stackedBody(context, invoice, settings);

        final side = Padding(
          padding: const EdgeInsets.all(Dimensions.spaceM),
          child: invoice.isOpen
              ? _OpenSidePanel(
                  invoice: invoice,
                  settings: settings,
                  busy: _busy,
                  onCheckout: () => _checkout(invoice, settings),
                )
              : SingleChildScrollView(
                  child: _ClosedSidePanel(
                    invoice: invoice,
                    settings: settings,
                    busy: _busy,
                    onPrint: () => _print(invoice, settings),
                    onSave: () => _savePdf(invoice, settings),
                    onPreview: () => _preview(invoice, settings),
                  ),
                ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: _LinesColumn(invoice: invoice)),
            VerticalDivider(width: 1, color: AppColors.divider),
            SizedBox(width: 440, child: side),
          ],
        );
      },
    );
  }

  Widget _stackedBody(
    BuildContext context,
    Invoice invoice,
    AppSettings settings,
  ) {
    final pad = context.isPhone ? Dimensions.spaceM : Dimensions.spaceL;

    if (!invoice.isOpen) {
      // فاتورة مغلقة: صفحة واحدة تتمرر (الأسطر ثم التفاصيل وأزرار الطباعة).
      return _LinesColumn(
        invoice: invoice,
        padding: EdgeInsets.all(pad),
        footer: [
          const SizedBox(height: Dimensions.spaceL),
          Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: Dimensions.spaceM),
          _ClosedSidePanel(
            invoice: invoice,
            settings: settings,
            busy: _busy,
            onPrint: () => _print(invoice, settings),
            onSave: () => _savePdf(invoice, settings),
            onPreview: () => _preview(invoice, settings),
          ),
        ],
      );
    }

    // فاتورة مفتوحة: الأسطر والملخص بمنطقة تتمرر، وقائمة المشتريات بمنطقة ثانية تتمرر،
    // وشريط المحاسبة ثابت أسفل الشاشة دائمًا.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _LinesColumn(
            invoice: invoice,
            padding: EdgeInsets.all(pad),
            footer: [
              const SizedBox(height: Dimensions.spaceL),
              InvoiceSummaryCard(
                invoice: invoice,
                policy: settings.billingPolicy,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        Expanded(
          flex: 4,
          child: ListView(
            padding: EdgeInsets.all(pad),
            children: [
              const SectionTitle(
                title: 'إضافة من قائمة المشتريات',
                icon: Icons.restaurant_menu_rounded,
              ),
              const SizedBox(height: Dimensions.spaceS),
              MenuPickerPanel(invoiceId: invoice.id, shrinkWrap: true),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        _CheckoutBar(
          invoice: invoice,
          settings: settings,
          busy: _busy,
          horizontalPadding: pad,
          onCheckout: () => _checkout(invoice, settings),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsCubit>().state.settings;
    final narrow = context.isPhone;

    return StreamBuilder<Invoice?>(
      stream: _stream,
      builder: (context, snapshot) {
        final invoice = snapshot.data;

        if (invoice == null) {
          return Scaffold(
            appBar: AppBar(),
            body: snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : const EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'الفاتورة غير موجودة',
                  ),
          );
        }

        final badge = StatusBadge(
          label: invoice.isOpen ? 'مفتوحة' : 'مغلقة',
          color: invoice.isOpen
              ? AppColors.statusAvailable
              : AppColors.textSecondary,
          icon: invoice.isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
        );

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            titleSpacing: narrow ? 0 : null,
            // شاشة ضيقة: رقم الفاتورة فوق واسم الزبون تحته (مع قص بنقاط)،
            // والشارة تنتقل إلى أقصى الشريط بدل أن تضغط الاسم.
            title: narrow
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فاتورة #${invoice.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading3(),
                      ),
                      Text(
                        invoice.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall(AppColors.secondary),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Text('فاتورة #${invoice.id}'),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          '— ${invoice.customerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.heading2(AppColors.secondary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      badge,
                    ],
                  ),
            actions: [
              if (invoice.isOpen && invoice.isEmpty)
                narrow
                    ? IconButton(
                        tooltip: 'حذف الفاتورة الفارغة',
                        onPressed: () => _deleteEmpty(invoice),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: () => _deleteEmpty(invoice),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                        ),
                        label: Text(
                          'حذف الفاتورة الفارغة',
                          style: AppTextStyles.button(AppColors.danger),
                        ),
                      ),
              if (narrow) ...[const SizedBox(width: 4), badge],
              const SizedBox(width: 12),
            ],
          ),
          body: _body(context, invoice, settings),
        );
      },
    );
  }
}

class _LinesColumn extends StatelessWidget {
  final Invoice invoice;
  final EdgeInsetsGeometry? padding;

  /// عناصر تُضاف بعد قائمة المشتريات داخل نفس التمرير (للتخطيط الضيق).
  final List<Widget> footer;

  const _LinesColumn({
    required this.invoice,
    this.padding,
    this.footer = const [],
  });

  @override
  Widget build(BuildContext context) {
    final editable = invoice.isOpen;
    return ListView(
      padding: padding ?? const EdgeInsets.all(Dimensions.spaceL),
      children: [
        SectionTitle(
          title: 'اللعب',
          icon: Icons.sports_esports_rounded,
          trailing: editable
              ? FilledButton.icon(
                  onPressed: () =>
                      showStartPlayDialog(context, fixedInvoiceId: invoice.id),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة لعب'),
                )
              : null,
        ),
        const SizedBox(height: Dimensions.spaceS),
        if (invoice.playLines.isEmpty)
          _HintBox(
            text: editable
                ? 'لم يبدأ أي لعب بعد. اضغط "إضافة لعب" واختر الجهاز أو الطاولة.'
                : 'لا يوجد لعب في هذه الفاتورة.',
          )
        else
          for (final line in invoice.playLines)
            Padding(
              padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
              child: PlayLineTile(line: line, editable: editable),
            ),
        const SizedBox(height: Dimensions.spaceL),
        const SectionTitle(title: 'المشتريات', icon: Icons.fastfood_rounded),
        const SizedBox(height: Dimensions.spaceS),
        if (invoice.itemLines.isEmpty)
          _HintBox(
            text: editable
                ? 'لا مشتريات بعد. اختر من قائمة المشتريات لإضافة مشروب أو أكلة.'
                : 'لا توجد مشتريات في هذه الفاتورة.',
          )
        else
          for (final item in invoice.itemLines)
            Padding(
              padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
              child: ItemLineTile(line: item, editable: editable),
            ),
        ...footer,
      ],
    );
  }
}

class _HintBox extends StatelessWidget {
  final String text;
  const _HintBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Dimensions.spaceM),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: AppTextStyles.bodyMedium(AppColors.textMuted)),
    );
  }
}

/// زر "محاسبة وإغلاق" (مشترك بين اللوحة الجانبية وشريط المحاسبة السفلي).
class _CheckoutButton extends StatelessWidget {
  final bool busy;
  final bool disabled;
  final String label;
  final VoidCallback onCheckout;

  const _CheckoutButton({
    required this.busy,
    required this.disabled,
    required this.label,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Dimensions.buttonHeightLarge,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.black,
        ),
        onPressed: (busy || disabled) ? null : onCheckout,
        icon: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.point_of_sale_rounded),
        label: Text(label),
      ),
    );
  }
}

/// شريط ثابت أسفل صفحة الفاتورة المفتوحة في الشاشات الضيقة: الإجمالي الحي
/// وزر المحاسبة يبقيان ظاهرين دائمًا مهما طالت الأسطر وقائمة المشتريات.
class _CheckoutBar extends StatelessWidget {
  final Invoice invoice;
  final AppSettings settings;
  final bool busy;
  final double horizontalPadding;
  final VoidCallback onCheckout;

  const _CheckoutBar({
    required this.invoice,
    required this.settings,
    required this.busy,
    required this.horizontalPadding,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        10,
        horizontalPadding,
        10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('الإجمالي الحالي', style: AppTextStyles.bodySmall()),
                    LiveBuilder(
                      builder: (context, now) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          formatMoneyWithUnit(
                            invoice
                                .totalsAt(now, settings.billingPolicy)
                                .finalTotal,
                          ),
                          style: AppTextStyles.timer(AppColors.secondary, 24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Dimensions.spaceS),
              _CheckoutButton(
                busy: busy,
                disabled: invoice.isEmpty,
                label: 'محاسبة وإغلاق',
                onCheckout: onCheckout,
              ),
            ],
          ),
          if (invoice.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'أضف لعبًا أو صنفًا لتتمكن من المحاسبة.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall(),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpenSidePanel extends StatelessWidget {
  final Invoice invoice;
  final AppSettings settings;
  final bool busy;
  final VoidCallback onCheckout;

  const _OpenSidePanel({
    required this.invoice,
    required this.settings,
    required this.busy,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          title: 'إضافة من قائمة المشتريات',
          icon: Icons.restaurant_menu_rounded,
        ),
        const SizedBox(height: Dimensions.spaceS),
        Expanded(child: MenuPickerPanel(invoiceId: invoice.id)),
        const SizedBox(height: Dimensions.spaceM),
        InvoiceSummaryCard(invoice: invoice, policy: settings.billingPolicy),
        const SizedBox(height: Dimensions.spaceM),
        _CheckoutButton(
          busy: busy,
          disabled: invoice.isEmpty,
          label: 'محاسبة وإغلاق الفاتورة',
          onCheckout: onCheckout,
        ),
        if (invoice.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'أضف لعبًا أو صنفًا لتتمكن من المحاسبة.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall(),
            ),
          ),
      ],
    );
  }
}

/// تفاصيل الفاتورة المغلقة. بدون Spacer وبحجم محتواها، فتوضع داخل أي تمرير.
class _ClosedSidePanel extends StatelessWidget {
  final Invoice invoice;
  final AppSettings settings;
  final bool busy;
  final VoidCallback onPrint;
  final VoidCallback onSave;
  final VoidCallback onPreview;

  const _ClosedSidePanel({
    required this.invoice,
    required this.settings,
    required this.busy,
    required this.onPrint,
    required this.onSave,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          title: 'تفاصيل الفاتورة',
          icon: Icons.receipt_long_rounded,
        ),
        const SizedBox(height: Dimensions.spaceS),
        Text(
          'أُنشئت ${formatDateTime(invoice.createdAt)}'
          '${invoice.closedAt == null ? '' : '\nأُغلقت ${formatDateTime(invoice.closedAt!)}'}',
          style: AppTextStyles.bodyMedium(AppColors.textSecondary),
        ),
        const SizedBox(height: Dimensions.spaceM),
        InvoiceSummaryCard(invoice: invoice, policy: settings.billingPolicy),
        const SizedBox(height: Dimensions.spaceL),
        SizedBox(
          height: Dimensions.buttonHeightLarge,
          child: FilledButton.icon(
            onPressed: busy ? null : onPrint,
            icon: const Icon(Icons.print_rounded),
            label: const Text('طباعة الفاتورة'),
          ),
        ),
        const SizedBox(height: Dimensions.spaceS),
        OutlinedButton.icon(
          onPressed: onPreview,
          icon: const Icon(Icons.visibility_rounded),
          label: const Text('معاينة (واختيار طابعة)'),
        ),
        const SizedBox(height: Dimensions.spaceS),
        OutlinedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('حفظ كملف PDF'),
        ),
        const SizedBox(height: Dimensions.spaceL),
        Text(
          'الفاتورة المغلقة للقراءة فقط ولا يمكن تعديلها.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall(AppColors.textMuted),
        ),
      ],
    );
  }
}
