import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/date_range_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/section_title.dart';
import '../../domain/entities/report.dart';
import '../cubit/reports_cubit.dart';
import '../widgets/stat_widgets.dart';

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

  static String _money(int v) => formatMoneyWithUnit(Money(v));

  static String _hours(int minutes) {
    if (minutes < 60) return '$minutes دقيقة';
    final h = minutes / 60;
    return '${h.toStringAsFixed(h >= 10 ? 0 : 1)} ساعة';
  }

  static String _dayLabel(DailySales d) {
    final t = DateTime.tryParse(d.date);
    return t == null ? d.date : '${arabicDayName(t)}  ${d.date.substring(5)}';
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

    final best = report.bestDay;
    final worst = report.worstDay;
    final peak = report.peakHour;
    final topRevenue = report.topByRevenue.isEmpty ? null : report.topByRevenue.first;
    final topMinutes = report.topByMinutes.isEmpty ? null : report.topByMinutes.first;
    final topBooked = report.topByBookings.isEmpty ? null : report.topByBookings.first;
    final topItem =
        report.topItemsByQuantity.isEmpty ? null : report.topItemsByQuantity.first;
    // لون واحد لكل مجموعة؛ الأخضر والأحمر محجوزان لمعنى (أفضل/أضعف).
    const cSales = AppColors.secondary;
    final cIncome = AppColors.primaryLight;
    const cActivity = AppColors.info;
    const cBest = AppColors.warning;
    final pad = context.isPhone ? Dimensions.spaceM : Dimensions.spaceL;

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
      children: [
        // ── 1) المبيعات ───────────────────────────────────────────────
        const SectionTitle(
            title: 'المبيعات', icon: Icons.payments_rounded, color: cSales),
        const SizedBox(height: Dimensions.spaceS),
        KpiGrid(children: [
          KpiCard(
            label: 'إجمالي المبيعات',
            value: _money(s.revenue),
            hint: 'من ${s.invoiceCount} فاتورة مغلقة',
            icon: Icons.payments_rounded,
            color: cSales,
          ),
          KpiCard(
            label: 'متوسط الفاتورة',
            value: _money(s.averageInvoice),
            hint: 'إجمالي المبيعات ÷ عدد الفواتير',
            icon: Icons.analytics_rounded,
            color: cSales,
          ),
          KpiCard(
            label: 'أعلى فاتورة',
            value: _money(s.maxInvoice),
            icon: Icons.trending_up_rounded,
            color: cSales,
          ),
        ]),

        // ── 2) مصادر الدخل: اللعب مقابل المأكولات ─────────────────────
        const SizedBox(height: Dimensions.spaceL),
        SectionTitle(
            title: 'مصادر الدخل',
            icon: Icons.account_balance_wallet_rounded,
            color: cIncome),
        const SizedBox(height: Dimensions.spaceS),
        KpiGrid(children: [
          KpiCard(
            label: 'إيراد اللعب',
            value: _money(s.playRevenue),
            hint: '${s.playSharePercent}% من الإجمالي',
            icon: Icons.sports_esports_rounded,
            color: cIncome,
          ),
          KpiCard(
            label: 'إيراد المأكولات والمشروبات',
            value: _money(s.itemsRevenue),
            hint: '${s.itemsSharePercent}% من الإجمالي',
            icon: Icons.fastfood_rounded,
            color: cIncome,
          ),
        ]),

        // ── 2-ب) تفصيل إيراد اللعب حسب النوع ─────────────────────────
        if (report.revenueByKind.isNotEmpty) ...[
          const SizedBox(height: Dimensions.spaceL),
          SectionTitle(
              title: 'إيراد اللعب حسب النوع',
              icon: Icons.category_rounded,
              color: cIncome),
          const SizedBox(height: Dimensions.spaceS),
          KpiGrid(children: [
            for (final k in report.revenueByKind)
              KpiCard(
                label: k.label,
                value: _money(k.revenue),
                hint: s.playRevenue == 0
                    ? null
                    : '${(k.revenue * 100 / s.playRevenue).round()}% من إيراد اللعب',
                icon: Icons.category_rounded,
                color: cIncome,
              ),
          ]),
        ],

        // ── 3) نشاط الصالة ────────────────────────────────────────────
        const SizedBox(height: Dimensions.spaceL),
        const SectionTitle(
            title: 'نشاط الصالة', icon: Icons.timer_rounded, color: cActivity),
        const SizedBox(height: Dimensions.spaceS),
        KpiGrid(children: [
          KpiCard(
            label: 'عدد جلسات اللعب',
            value: '${s.sessions}',
            icon: Icons.play_circle_rounded,
            color: cActivity,
          ),
          KpiCard(
            label: 'إجمالي ساعات اللعب',
            value: _hours(s.playMinutes),
            icon: Icons.hourglass_bottom_rounded,
            color: cActivity,
          ),
          KpiCard(
            label: 'متوسط مدة الجلسة',
            value: describeMinutes(s.averageSessionMinutes),
            icon: Icons.av_timer_rounded,
            color: cActivity,
          ),
          if (peak != null)
            KpiCard(
              label: 'ساعة الذروة',
              value: formatHourMinute(peak.hour, 0),
              hint: '${peak.sessions} جلسة بدأت فيها',
              icon: Icons.schedule_rounded,
              color: cActivity,
            ),
          KpiCard(
            label: 'الحجوزات',
            value: '${report.bookingsCount}',
            hint: report.cancelledBookings == 0
                ? 'لا توجد حجوزات ملغاة'
                : '${report.cancelledBookings} حجز ملغى',
            icon: Icons.event_available_rounded,
            color: cActivity,
          ),
        ]),

        // ── 4) الأيام (فقط عند وجود أكثر من يوم) ─────────────────────
        if (report.activeDays > 1 && best != null && worst != null) ...[
          const SizedBox(height: Dimensions.spaceL),
          const SectionTitle(
              title: 'الأيام',
              icon: Icons.calendar_month_rounded,
              color: cActivity),
          const SizedBox(height: Dimensions.spaceS),
          KpiGrid(children: [
            KpiCard(
              label: 'متوسط المبيعات اليومي',
              value: _money(report.averageDaily),
              hint: 'على ${report.activeDays} يوم عمل',
              icon: Icons.calendar_view_day_rounded,
              color: cActivity,
            ),
            KpiCard(
              label: 'أفضل يوم',
              value: _money(best.revenue),
              hint: _dayLabel(best),
              icon: Icons.arrow_upward_rounded,
              color: AppColors.success,
            ),
            KpiCard(
              label: 'أضعف يوم',
              value: _money(worst.revenue),
              hint: _dayLabel(worst),
              icon: Icons.arrow_downward_rounded,
              color: AppColors.danger,
            ),
          ]),
        ],

        // ── 5) الأفضل أداءً ───────────────────────────────────────────
        const SizedBox(height: Dimensions.spaceL),
        const SectionTitle(
            title: 'الأفضل أداءً',
            icon: Icons.emoji_events_rounded,
            color: cBest),
        const SizedBox(height: Dimensions.spaceS),
        KpiGrid(children: [
          if (topRevenue != null)
            KpiCard(
              label: 'الأكثر ربحًا',
              value: topRevenue.name,
              hint: _money(topRevenue.revenue),
              icon: Icons.emoji_events_rounded,
              color: cBest,
            ),
          if (topMinutes != null)
            KpiCard(
              label: 'الأكثر لعبًا',
              value: topMinutes.name,
              hint: _hours(topMinutes.minutes),
              icon: Icons.timer_rounded,
              color: cBest,
            ),
          if (topBooked != null)
            KpiCard(
              label: 'الأكثر حجزًا',
              value: topBooked.resourceName,
              hint: '${topBooked.count} حجز',
              icon: Icons.event_available_rounded,
              color: cBest,
            ),
          if (topItem != null)
            KpiCard(
              label: 'الصنف الأكثر مبيعًا',
              value: topItem.name,
              hint: '${topItem.quantity} قطعة  •  ${_money(topItem.revenue)}',
              icon: Icons.local_fire_department_rounded,
              color: cBest,
            ),
        ]),
      ],
    );
  }
}
