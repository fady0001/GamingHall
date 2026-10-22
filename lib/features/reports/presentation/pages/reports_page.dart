import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/date_range_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/section_title.dart';
import '../../domain/entities/report.dart';
import '../cubit/reports_cubit.dart';
import '../widgets/stat_widgets.dart';
import '../../../resources/domain/entities/resource_kind.dart';

/// التقارير والإحصائيات (للمدير فقط).
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  @override
  void initState() {
    super.initState();
    context.read<ReportsCubit>().load();
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    // إن كانت هناك فترة مخصصة محددة سابقًا نفتح المنتقي عليها (النهاية مخزّنة
    // نصف مفتوحة فننقص يومًا لنعرض آخر يوم فعلي).
    final saved = context.read<ReportsCubit>().state.custom;
    final today = DateTime(now.year, now.month, now.day);
    var initial = DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
    if (saved != null) {
      final savedEnd = DateTime(saved.end.year, saved.end.month, saved.end.day - 1);
      if (!savedEnd.isBefore(saved.start) && !savedEnd.isAfter(today)) {
        initial = DateTimeRange(start: saved.start, end: savedEnd);
      }
    }
    final picked = await showDateRangeDialog(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialRange: initial,
      title: 'اختيار الفترة',
    );
    if (picked == null || !mounted) return;
    // النهاية نصف مفتوحة: نضيف يومًا ليشمل اليوم الأخير كاملًا.
    final range = DateRange(
      DateTime(picked.start.year, picked.start.month, picked.start.day),
      DateTime(picked.end.year, picked.end.month, picked.end.day + 1),
    );
    context.read<ReportsCubit>().load(preset: RangePreset.custom, custom: range);
  }

  String _rangeLabel(Report r) {
    final lastDay = r.range.end.subtract(const Duration(milliseconds: 1));
    final a = formatDate(r.range.start);
    final b = formatDate(lastDay);
    return a == b ? a : '$a  →  $b';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ReportsCubit>().state;
    final report = state.report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'التقارير والإحصائيات',
          subtitle: report == null ? null : 'الفترة: ${_rangeLabel(report)}  •  الأرقام من الفواتير المغلقة فقط',
          actions: [
            IconButton.outlined(
              tooltip: 'تحديث',
              onPressed: () => context.read<ReportsCubit>().load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: context.isPhone ? Dimensions.spaceM : Dimensions.spaceL),
          child: Wrap(
            spacing: Dimensions.spaceS,
            runSpacing: Dimensions.spaceS,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<RangePreset>(
                showSelectedIcon: false,
                segments: [
                  for (final p in [RangePreset.today, RangePreset.week, RangePreset.month])
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: state.preset == RangePreset.custom
                    ? <RangePreset>{}
                    : {state.preset},
                emptySelectionAllowed: true,
                onSelectionChanged: (s) {
                  if (s.isEmpty) return;
                  context.read<ReportsCubit>().load(preset: s.first);
                },
              ),
              _CustomRangeButton(
                selected: state.preset == RangePreset.custom,
                onPressed: _pickCustom,
              ),
              if (state.isLoading) ...[
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ],
            ],
          ),
        ),
        const SizedBox(height: Dimensions.spaceM),
        Expanded(
          child: report == null
              ? (state.error != null
                  ? EmptyState(icon: Icons.error_outline_rounded, title: state.error!)
                  : const Center(child: CircularProgressIndicator()))
              : _ReportBody(report: report),
        ),
      ],
    );
  }
}

/// زر "فترة مخصصة": يتلوّن بنفس مظهر الخيار المحدد في أزرار (يوم العمل الحالي /
/// هذا الأسبوع / هذا الشهر) عندما تكون الفترة المخصصة هي المعروضة حاليًا.
class _CustomRangeButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onPressed;
  const _CustomRangeButton({required this.selected, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // نفس مظهر الخيار المحدد في SegmentedButton بهذا الثيم.
    final fg = AppColors.isDark ? AppColors.textPrimary : AppColors.primaryLight;
    final style = selected
        ? OutlinedButton.styleFrom(
            backgroundColor:
                AppColors.primary.withValues(alpha: AppColors.isDark ? 0.24 : 0.16),
            foregroundColor: fg,
            side: const BorderSide(color: AppColors.primary),
            textStyle: AppTextStyles.button(fg),
          )
        : null;
    return OutlinedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(selected ? Icons.check_rounded : Icons.date_range_rounded),
      label: const Text('فترة مخصصة'),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final Report report;
  const _ReportBody({required this.report});

  String _hours(int minutes) {
    final h = minutes / 60;
    return '${h.toStringAsFixed(h >= 10 ? 0 : 1)} ساعة';
  }

  @override
  Widget build(BuildContext context) {
    final s = report.summary;

    if (s.invoiceCount == 0) {
      return const EmptyState(
        icon: Icons.insights_rounded,
        title: 'لا توجد فواتير مغلقة في هذه الفترة',
        message: 'ستظهر الإحصائيات هنا بعد محاسبة الفواتير.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Dimensions.spaceL, 0, Dimensions.spaceL, Dimensions.spaceL),
      children: [
        AdaptiveExpandedRow(
          children: [
            Expanded(
              child: KpiCard(
                label: 'إجمالي المبيعات',
                value: formatMoneyWithUnit(Money(s.revenue)),
                icon: Icons.payments_rounded,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(width: Dimensions.spaceM),
            Expanded(
              child: KpiCard(
                label: 'عدد الفواتير',
                value: '${s.invoiceCount}',
                icon: Icons.receipt_long_rounded,
                color: AppColors.primaryLight,
              ),
            ),
            const SizedBox(width: Dimensions.spaceM),
            Expanded(
              child: KpiCard(
                label: 'متوسط الفاتورة',
                value: formatMoneyWithUnit(Money(s.averageInvoice)),
                icon: Icons.analytics_rounded,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimensions.spaceM),
        AdaptiveExpandedRow(
          children: [
            Expanded(
              child: KpiCard(
                label: 'إيراد اللعب',
                value: formatMoneyWithUnit(Money(s.playRevenue)),
                icon: Icons.sports_esports_rounded,
                color: AppColors.statusBusy,
              ),
            ),
            const SizedBox(width: Dimensions.spaceM),
            Expanded(
              child: KpiCard(
                label: 'إيراد المأكولات والمشروبات',
                value: formatMoneyWithUnit(Money(s.itemsRevenue)),
                icon: Icons.fastfood_rounded,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimensions.spaceL),
        if (report.daily.length > 1) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(title: 'المبيعات اليومية', icon: Icons.bar_chart_rounded),
                const SizedBox(height: Dimensions.spaceM),
                SimpleBarChart(
                  data: [
                    for (final d in report.daily)
                      BarDatum(
                        d.date.substring(5),
                        d.revenue,
                        groupThousands(d.revenue),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
        ],
        AdaptiveExpandedRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _panel(
                'الأكثر ربحًا',
                Icons.emoji_events_rounded,
                RankList(items: [
                  for (final r in report.topByRevenue)
                    RankItem(r.name, r.revenue, formatMoneyWithUnit(Money(r.revenue))),
                ]),
              ),
            ),
            const SizedBox(width: Dimensions.spaceM),
            Expanded(
              child: _panel(
                'الأكثر لعبًا (بالساعات)',
                Icons.timer_rounded,
                RankList(
                  color: AppColors.statusBusy,
                  items: [
                    for (final r in report.topByMinutes)
                      RankItem(r.name, r.minutes, _hours(r.minutes)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimensions.spaceM),
        AdaptiveExpandedRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _panel(
                'الأكثر حجزًا',
                Icons.event_available_rounded,
                RankList(
                  color: AppColors.warning,
                  items: [
                    for (final b in report.topByBookings)
                      RankItem(b.resourceName, b.count, '${b.count} حجز'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Dimensions.spaceM),
            Expanded(
              child: _panel(
                'الأصناف الأكثر مبيعًا',
                Icons.local_fire_department_rounded,
                RankList(
                  color: AppColors.accent,
                  items: [
                    for (final i in report.topItemsByQuantity)
                      RankItem(i.name, i.quantity, '${i.quantity} قطعة'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimensions.spaceM),
        AdaptiveExpandedRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _panel(
                'الإيراد حسب نوع اللعب',
                Icons.pie_chart_rounded,
                RankList(
                  items: [
                    for (final k in report.revenueByKind)
                      RankItem(k.label, k.revenue, formatMoneyWithUnit(Money(k.revenue))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Dimensions.spaceM),
            Expanded(
              child: _panel(
                'ساعات الذروة (بداية اللعب)',
                Icons.schedule_rounded,
                report.busiestHours.isEmpty
                    ? Text('لا توجد بيانات', style: AppTextStyles.bodyMedium(AppColors.textMuted))
                    : SimpleBarChart(
                        height: 170,
                        color: AppColors.secondary,
                        data: [
                          for (final h in report.busiestHours)
                            BarDatum(formatHourMinute(h.hour, 0), h.sessions, '${h.sessions}'),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _panel(String title, IconData icon, Widget child) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title: title, icon: icon),
          const SizedBox(height: Dimensions.spaceS),
          child,
        ],
      ),
    );
  }
}
