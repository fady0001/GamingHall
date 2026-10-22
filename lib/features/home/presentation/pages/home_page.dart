import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../days/presentation/cubit/work_day_cubit.dart';
import '../../../invoices/domain/entities/invoice.dart';
import '../../../invoices/presentation/cubit/invoices_cubit.dart';
import '../../../invoices/presentation/pages/invoice_detail_page.dart';
import '../../../invoices/presentation/widgets/new_invoice_dialog.dart';
import '../../../invoices/presentation/widgets/start_play_dialog.dart';
import '../../../resources/domain/entities/resource_kind.dart';
import '../../../resources/domain/entities/resource_status.dart';
import '../../../resources/domain/usecases/build_resource_views.dart';
import '../../../resources/presentation/cubit/devices_board_cubit.dart';
import '../../../shell/presentation/nav_cubit.dart';
import '../widgets/device_card.dart';
import '../widgets/open_invoice_card.dart';

/// الشاشة الرئيسية للموظف = الفواتير (مفتوحة / أُغلقت اليوم). ولوحة الأجهزة بحالاتها
/// في صفحة "الأجهزة" المنفصلة.
enum HomeSection { invoices, devices }

class HomePage extends StatefulWidget {
  final HomeSection section;
  const HomePage({super.key, this.section = HomeSection.invoices});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showClosed = false;
  ResourceStatus? _statusFilter;

  void _openInvoice(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InvoiceDetailPage(invoiceId: id)),
    );
  }

  Future<void> _newInvoice() async {
    final invoice = await showNewInvoiceDialog(context);
    if (invoice != null && mounted) _openInvoice(invoice.id);
  }

  void _onDeviceTap(ResourceView view) {
    switch (view.status) {
      case ResourceStatus.available:
      case ResourceStatus.reserved:
        showStartPlayDialog(context, fixedResourceId: view.resource.id);
      case ResourceStatus.busy:
        final id = view.runningInvoice?.id;
        if (id != null) _openInvoice(id);
      case ResourceStatus.outOfService:
        showAppSnack(
          context,
          '"${view.resource.name}" خارج الخدمة. المدير يعيده للخدمة من صفحة "الأجهزة والأسعار".',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = context.watch<InvoicesCubit>().state;
    final day = context.watch<WorkDayCubit>().state.currentDay;
    final isManager = context.select((AuthCubit c) => c.state.isManager);

    final closedToday = invoices.todayClosed;
    final revenue = closedToday.fold<int>(
        0, (s, i) => s + (i.settledTotals?.finalTotal.amount ?? 0));

    final isInvoices = widget.section == HomeSection.invoices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: isInvoices ? 'الفواتير' : 'الأجهزة',
          subtitle: day == null
              ? null
              : 'يوم العمل: ${day.label}  •  بدأ ${formatClock(day.startedAt)}'
                  '${isManager ? '  •  مبيعات اليوم: ${formatMoneyWithUnit(Money(revenue))}' : ''}',
          // زر "فاتورة جديدة" في صفحة الفواتير فقط؛ صفحة الأجهزة بدونه.
          actions: isInvoices
              ? [
                  SizedBox(
                    height: Dimensions.buttonHeightLarge,
                    child: FilledButton.icon(
                      onPressed: _newInvoice,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('فاتورة جديدة'),
                    ),
                  ),
                ]
              : const [],
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              context.isPhone ? Dimensions.spaceM : Dimensions.spaceL,
              0,
              context.isPhone ? Dimensions.spaceM : Dimensions.spaceL,
              context.isPhone ? Dimensions.spaceM : Dimensions.spaceL,
            ),
            child: isInvoices
                ? _invoicesPane(invoices, closedToday)
                : _devicesPane(isManager),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ الفواتير

  Widget _invoicesPane(InvoicesState state, List<Invoice> closedToday) {
    final list = _showClosed ? closedToday : state.open;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text('مفتوحة (${state.open.length})')),
            ButtonSegment(value: true, label: Text('أُغلقت اليوم (${closedToday.length})')),
          ],
          selected: {_showClosed},
          onSelectionChanged: (s) => setState(() => _showClosed = s.first),
        ),
        const SizedBox(height: Dimensions.spaceM),
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? EmptyState(
                      icon: _showClosed
                          ? Icons.receipt_long_rounded
                          : Icons.person_add_alt_1_rounded,
                      title: _showClosed
                          ? 'لا فواتير مغلقة اليوم بعد'
                          : 'لا توجد فواتير مفتوحة',
                      message: _showClosed
                          ? null
                          : 'عندما يصل زبون اضغط "فاتورة جديدة"، أو اضغط على جهاز متاح لبدء اللعب مباشرة.',
                      action: _showClosed
                          ? null
                          : FilledButton.icon(
                              onPressed: _newInvoice,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('فاتورة جديدة'),
                            ),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Dimensions.spaceS),
                      itemBuilder: (context, i) => InvoiceCard(
                        invoice: list[i],
                        onTap: () => _openInvoice(list[i].id),
                      ),
                    ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- الأجهزة

  Widget _devicesPane(bool isManager) {
    final board = context.watch<DevicesBoardCubit>().state;

    if (board.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (board.views.isEmpty) {
      return EmptyState(
        icon: Icons.sports_esports_rounded,
        title: 'لم تُضف أي أجهزة بعد',
        message: isManager
            ? 'أضف الشاشات والكمبيوترات والطاولات مع أسعارها لتبدأ التشغيل.'
            : 'اطلب من المدير إضافة الأجهزة والطاولات.',
        action: isManager
            ? FilledButton.icon(
                onPressed: () => context.read<NavCubit>().go(Destination.resources),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة الأجهزة'),
              )
            : null,
      );
    }

    final filtered = board.views
        .where((v) => _statusFilter == null || v.status == _statusFilter)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip(null, 'الكل', board.views.length, AppColors.primaryLight),
              for (final s in ResourceStatus.values)
                _filterChip(s, s.label, board.countOf(s), AppColors.forStatus(s)),
            ],
          ),
        ),
        const SizedBox(height: Dimensions.spaceM),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.filter_alt_off_rounded,
                  title: 'لا توجد أجهزة بهذه الحالة',
                )
              : ListView(
                  children: [
                    for (final group in ResourceGroup.values)
                      ..._groupSection(group, filtered),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _filterChip(ResourceStatus? status, String label, int count, Color color) {
    final selected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        selectedColor: color.withValues(alpha: 0.22),
        side: BorderSide(color: selected ? color : AppColors.border),
        avatar: status == null
            ? null
            : Icon(status.icon, size: 16, color: color),
        label: Text('$label ($count)'),
        onSelected: (_) => setState(() => _statusFilter = status),
      ),
    );
  }

  List<Widget> _groupSection(ResourceGroup group, List<ResourceView> all) {
    final views = all.where((v) => v.resource.kind.group == group).toList();
    if (views.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: Dimensions.spaceS),
        child: Row(
          children: [
            Icon(group.icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(group.label, style: AppTextStyles.label()),
          ],
        ),
      ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          // ارتفاع يتسع لأطول حالة (مشغول بوقت محدد / محجوز بنص يلتف سطرين).
          mainAxisExtent: 176,
          crossAxisSpacing: Dimensions.spaceS,
          mainAxisSpacing: Dimensions.spaceS,
        ),
        itemCount: views.length,
        itemBuilder: (context, i) => DeviceCard(
          view: views[i],
          onTap: () => _onDeviceTap(views[i]),
        ),
      ),
      const SizedBox(height: Dimensions.spaceM),
    ];
  }
}
