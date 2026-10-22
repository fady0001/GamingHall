import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../invoices/presentation/pages/invoice_detail_page.dart';
import '../../../resources/domain/entities/resource_kind.dart';
import '../../../resources/presentation/cubit/resources_cubit.dart';
import '../../domain/entities/booking.dart';
import '../../domain/usecases/booking_rules.dart';
import '../cubit/bookings_cubit.dart';
import '../widgets/booking_dialog.dart';

/// الحجوزات: عرض يوم محدد مع التنقل بين الأيام، وبحث بالاسم/الهاتف عبر كل الأيام.
class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  late DateTime _day;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _shift(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _convert(Booking b) async {
    final cubit = context.read<BookingsCubit>();
    try {
      final invoiceId = await cubit.convertToInvoice(b.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailPage(invoiceId: invoiceId),
        ),
      );
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _cancel(Booking b) async {
    final ok = await showConfirmDialog(
      context,
      title: 'إلغاء الحجز؟',
      message:
          'سيُلغى حجز ${b.customerName} على ${b.resourceName} (${b.timeRangeLabel}).',
      confirmLabel: 'إلغاء الحجز',
      cancelLabel: 'تراجع',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<BookingsCubit>().cancel(b.id);
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BookingsCubit>().state;
    final searching = _search.text.trim().isNotEmpty;
    final list = filterBookings(
      state.bookings,
      day: searching ? null : _day,
      query: _search.text,
    );
    final today = DateTime.now();
    final isToday = isSameDay(_day, today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'الحجوزات',
          subtitle: searching
              ? 'نتائج البحث في كل الأيام'
              : '${arabicDayName(_day)}  ${formatDate(_day)}',
          actions: [
            SizedBox(
              height: Dimensions.buttonHeightLarge,
              child: FilledButton.icon(
                onPressed: () => showBookingDialog(context, initialDay: _day),
                icon: const Icon(Icons.add_rounded),
                label: const Text('حجز جديد'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceL),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: 'اليوم السابق',
                onPressed: searching ? null : () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              OutlinedButton.icon(
                onPressed: searching ? null : _pickDay,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(formatDate(_day)),
              ),
              IconButton.outlined(
                tooltip: 'اليوم التالي',
                onPressed: searching ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              if (!isToday)
                TextButton(
                  onPressed: searching
                      ? null
                      : () => setState(
                          () => _day = DateTime(
                            today.year,
                            today.month,
                            today.day,
                          ),
                        ),
                  child: const Text('العودة لليوم'),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 220,
                  maxWidth: context.isPhone ? double.infinity : 320,
                ),
                child: SizedBox(
                  width: context.isPhone
                      ? context.screenWidth - 2 * Dimensions.spaceL
                      : 320,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو الهاتف (كل الأيام)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: searching
                          ? IconButton(
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Dimensions.spaceM),
        Expanded(
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
              ? EmptyState(
                  icon: Icons.event_busy_rounded,
                  title: searching
                      ? 'لا توجد نتائج'
                      : 'لا توجد حجوزات في هذا اليوم',
                  message: searching ? null : 'اضغط "حجز جديد" لإضافة حجز.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Dimensions.spaceL,
                    0,
                    Dimensions.spaceL,
                    Dimensions.spaceL,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Dimensions.spaceS),
                  itemBuilder: (context, i) => _BookingTile(
                    booking: list[i],
                    showDate: searching,
                    onConvert: () => _convert(list[i]),
                    onCancel: () => _cancel(list[i]),
                    onOpenInvoice: list[i].convertedInvoiceId == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => InvoiceDetailPage(
                                invoiceId: list[i].convertedInvoiceId!,
                              ),
                            ),
                          ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking booking;
  final bool showDate;
  final VoidCallback onConvert;
  final VoidCallback onCancel;
  final VoidCallback? onOpenInvoice;

  const _BookingTile({
    required this.booking,
    required this.showDate,
    required this.onConvert,
    required this.onCancel,
    required this.onOpenInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final now = DateTime.now();
    final scheduled = b.status == BookingStatus.scheduled;
    final missed = scheduled && now.isAfter(b.endAt);

    final Color color;
    final String label;
    final IconData icon;
    if (b.status == BookingStatus.converted) {
      color = AppColors.statusAvailable;
      label = b.status.label;
      icon = Icons.check_circle_rounded;
    } else if (b.status == BookingStatus.cancelled) {
      color = AppColors.textMuted;
      label = b.status.label;
      icon = Icons.cancel_rounded;
    } else if (missed) {
      color = AppColors.danger;
      label = 'فات موعده';
      icon = Icons.history_toggle_off_rounded;
    } else {
      color = AppColors.warning;
      label = b.status.label;
      icon = Icons.schedule_rounded;
    }

    // عدد اللاعبين يظهر لحجوزات البلايستيشن فقط.
    var isPs = false;
    for (final r in context.watch<ResourcesCubit>().state.resources) {
      if (r.id == b.resourceId) isPs = r.kind == ResourceKind.playstation;
    }
    final details =
        '${b.resourceName}'
        '${isPs ? ' • ${b.playerCount} ${b.playerCount == 1 ? 'لاعب' : 'لاعبين'}' : ''}'
        '${b.phone.isEmpty ? '' : '  •  ${b.phone}'}';

    final timeBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatClock(b.startAt),
          style: AppTextStyles.timer(AppColors.textPrimary, 24),
        ),
        Text(
          b.isOpen ? 'وقت مفتوح' : 'إلى ${formatClock(b.endAt)}',
          style: AppTextStyles.bodySmall(),
        ),
        if (showDate)
          Text(
            formatDate(b.startAt),
            style: AppTextStyles.bodySmall(AppColors.secondary),
          ),
      ],
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(b.customerName, style: AppTextStyles.heading3()),
        const SizedBox(height: 2),
        Text(
          details,
          textDirection: TextDirection.rtl,
          style: AppTextStyles.bodyMedium(AppColors.textSecondary),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (scheduled && !missed)
          FilledButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('بدء اللعب'),
          ),
        if (scheduled)
          TextButton(
            onPressed: onCancel,
            child: Text('إلغاء', style: AppTextStyles.button(AppColors.danger)),
          ),
        if (onOpenInvoice != null)
          TextButton.icon(
            onPressed: onOpenInvoice,
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('الفاتورة'),
          ),
      ],
    );

    return AppCard(
      accentColor: scheduled && !missed ? AppColors.warning : null,
      child: LayoutBuilder(
        builder: (context, c) {
          // شاشة ضيقة: كل شيء عموديًا. واسعة: صف واحد كما كان.
          if (c.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    timeBlock,
                    const SizedBox(width: Dimensions.spaceM),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: Dimensions.spaceS),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(label: label, color: color, icon: icon),
                    actions,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 128, child: timeBlock),
              const SizedBox(width: Dimensions.spaceM),
              Expanded(child: info),
              StatusBadge(label: label, color: color, icon: icon),
              const SizedBox(width: Dimensions.spaceM),
              actions,
            ],
          );
        },
      ),
    );
  }
}
