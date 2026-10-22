import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/entities/billing_policy.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../days/domain/entities/work_day.dart';
import '../../../days/presentation/cubit/work_day_cubit.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../cubit/invoices_cubit.dart';
import 'invoice_detail_page.dart';

/// سجل الفواتير (للمدير فقط): قائمة أيام العمل وفواتير اليوم المختار. البحث
/// بالتاريخ داخل قائمة أيام العمل ولأيام العمل المسجّلة فقط، والبحث باسم
/// الزبون/رقم الفاتورة يمرّ على كل الأيام.
class InvoiceHistoryPage extends StatefulWidget {
  const InvoiceHistoryPage({super.key});

  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  int? _dayId;

  /// فلتر تاريخ يقتصر على قائمة أيام العمل (لا يبحث في الفواتير مباشرة).
  DateTime? _date;
  final _query = TextEditingController();
  Timer? _debounce;
  StreamSubscription<InvoicesState>? _sub;
  StreamSubscription<List<WorkDaySummary>>? _daysSub;
  List<WorkDaySummary>? _days;

  List<Invoice> _results = const [];
  bool _loading = true;
  int _requestId = 0;

  bool get _searching => _query.text.trim().isNotEmpty;

  /// أيام العمل المعروضة: كلها، أو التي تطابق التاريخ المختار.
  List<WorkDaySummary> get _visibleDays {
    final all = _days ?? const <WorkDaySummary>[];
    final d = _date;
    if (d == null) return all;
    final key = formatDate(d);
    return all.where((s) => s.day.dateKey == key).toList();
  }

  @override
  void initState() {
    super.initState();
    final cubit = context.read<InvoicesCubit>();
    _daysSub = context.read<WorkDayCubit>().watchSummaries().listen((list) {
      if (mounted) setState(() => _days = list);
    });
    // أي تغيير في الفواتير (إغلاق فاتورة مثلًا) يحدّث القائمة المعروضة.
    _sub = cubit.stream.listen((_) => _reload());
    _dayId = context.read<WorkDayCubit>().state.currentDay?.id;
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _daysSub?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final mine = ++_requestId;
    if (!_searching && _dayId == null) {
      // لم يُحدَّد يوم بعد (أول تشغيل) → ننتظر اليوم الحالي.
      _dayId = context.read<WorkDayCubit>().state.currentDay?.id;
      if (_dayId == null) return;
    }
    final filter = InvoiceSearchFilter(
      dayId: _searching ? null : _dayId,
      query: _query.text,
    );
    try {
      final list = await context.read<InvoicesCubit>().search(filter);
      if (!mounted || mine != _requestId) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted && mine == _requestId) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _reload);
  }

  /// اختيار تاريخ من أيام العمل المسجّلة فقط: يصفّي القائمة ويفتح اليوم المطابق.
  Future<void> _pickDate() async {
    final all = _days ?? const <WorkDaySummary>[];
    if (all.isEmpty) return;
    DateTime onlyDate(DateTime t) => DateTime(t.year, t.month, t.day);
    final keys = {for (final s in all) s.day.dateKey};
    final dates = all.map((s) => onlyDate(s.day.startedAt)).toList()..sort();
    final current = all
        .where((s) => s.day.id == _dayId)
        .map((s) => onlyDate(s.day.startedAt))
        .toList();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? (current.isNotEmpty ? current.first : dates.last),
      firstDate: dates.first,
      lastDate: dates.last,
      locale: const Locale('ar'),
      selectableDayPredicate: (d) => keys.contains(formatDate(d)),
      helpText: 'اختر يوم عمل',
    );
    if (picked == null || !mounted) return;
    final match = all.where((s) => s.day.dateKey == formatDate(picked)).toList();
    setState(() {
      _date = picked;
      _query.clear();
      if (match.isNotEmpty) _dayId = match.first.day.id;
    });
    _reload();
  }

  void _clearDateFilter() => setState(() => _date = null);

  void _clearFilters() {
    setState(_query.clear);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isManager = context.select((AuthCubit c) => c.state.isManager);
    final policy = context.watch<SettingsCubit>().state.settings.billingPolicy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'سجل الفواتير',
          subtitle:
              'تصفّح الفواتير حسب أيام العمل، أو ابحث باسم زبون أو رقم فاتورة',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceL),
          child: Wrap(
            spacing: Dimensions.spaceS,
            runSpacing: Dimensions.spaceS,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: context.isPhone
                    ? context.screenWidth - 2 * Dimensions.spaceL
                    : 340,
                child: TextField(
                  controller: _query,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'اسم الزبون أو رقم الفاتورة',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(_query.clear);
                              _reload();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              if (_searching) ...[
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('مسح البحث'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Dimensions.spaceM),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimensions.spaceL,
              0,
              Dimensions.spaceL,
              Dimensions.spaceL,
            ),
            // شاشة ضيقة: قائمة الأيام فوق قائمة الفواتير بدل جنبها.
            child: context.isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 150, child: _daysList(isManager)),
                      const SizedBox(height: Dimensions.spaceM),
                      Expanded(child: _invoicesList(policy, isManager)),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _invoicesList(policy, isManager)),
                      const SizedBox(width: Dimensions.spaceL),
                      SizedBox(width: 300, child: _daysList(isManager)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _invoicesList(BillingPolicy policy, bool isManager) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) {
      return EmptyState(
        icon: _searching
            ? Icons.search_off_rounded
            : Icons.receipt_long_rounded,
        title: _searching
            ? 'لا توجد فواتير مطابقة'
            : 'لا توجد فواتير في هذا اليوم',
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: Dimensions.spaceS),
      itemBuilder: (context, i) {
        final invoice = _results[i];
        return _HistoryTile(
          invoice: invoice,
          total: invoice.totalsAt(DateTime.now(), policy).finalTotal,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InvoiceDetailPage(invoiceId: invoice.id),
            ),
          ),
        );
      },
    );
  }

  Widget _daysList(bool isManager) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                Dimensions.spaceM, Dimensions.spaceXS, Dimensions.spaceXS, Dimensions.spaceXS),
            child: Row(
              children: [
                Expanded(child: Text('أيام العمل', style: AppTextStyles.heading3())),
                if (_date != null)
                  InputChip(
                    label: Text(formatDate(_date!)),
                    onDeleted: _clearDateFilter,
                    deleteButtonTooltipMessage: 'إلغاء فلتر التاريخ',
                  )
                else
                  TextButton.icon(
                    
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('بحث بتاريخ'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Builder(
              builder: (context) {
                final days = _visibleDays;
                if (_days == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (days.isEmpty) {
                  return Center(
                    child: Text('لا توجد أيام عمل', style: AppTextStyles.bodySmall()),
                  );
                }
                return ListView.builder(
                  itemCount: days.length,
                  itemBuilder: (context, i) {
                    final s = days[i];
                    final selected = !_searching && s.day.id == _dayId;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _dayId = s.day.id;
                          _query.clear();
                        });
                        _reload();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : Colors.transparent,
                          border: Border(
                            right: BorderSide(
                              color: selected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.day.label,
                                    style: AppTextStyles.bodyMedium().copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (s.day.isOpen)
                                  const StatusBadge(
                                    label: 'الحالي',
                                    color: AppColors.statusAvailable,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isManager
                                  ? '${s.invoiceCount} فاتورة • ${formatMoneyWithUnit(Money(s.totalRevenue))}'
                                  : '${s.invoiceCount} فاتورة مغلقة',
                              style: AppTextStyles.bodySmall(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Invoice invoice;
  final Money total;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.invoice,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final plays = invoice.playLines.length;
    final items = invoice.itemLines.fold<int>(0, (s, l) => s + l.quantity);
    final parts = <String>[
      if (plays > 0) '$plays لعب',
      if (items > 0) '$items صنف',
      formatClock(invoice.closedAt ?? invoice.createdAt),
    ];

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('#${invoice.id}', style: AppTextStyles.label()),
          ),
          const SizedBox(width: Dimensions.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.customerName, style: AppTextStyles.heading3()),
                Text(parts.join(' • '), style: AppTextStyles.bodySmall()),
              ],
            ),
          ),
          if (invoice.isOpen)
            const StatusBadge(
              label: 'مفتوحة',
              color: AppColors.statusAvailable,
              icon: Icons.lock_open_rounded,
            )
          else
            Text(formatMoneyWithUnit(total), style: AppTextStyles.price()),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
