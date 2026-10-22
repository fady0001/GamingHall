import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/alerts/alert_center.dart';
import '../../../core/platform/alert_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/time_format.dart';
import '../../bookings/domain/entities/booking.dart';
import '../../bookings/domain/usecases/booking_rules.dart';
import '../../bookings/presentation/cubit/bookings_cubit.dart';
import '../../invoices/domain/entities/invoice.dart';
import '../../invoices/presentation/cubit/invoices_cubit.dart';
import '../../invoices/presentation/pages/invoice_detail_page.dart';
import '../../settings/presentation/cubit/settings_cubit.dart';
import '../../../core/platform/window_service.dart';

/// يراقب الجلسات والحجوزات ويُطلق تنبيهين:
///  1) تذكير دوري (كل 15 أو 30 دقيقة بحسب الإعدادات) لكل لعب **مفتوح** جارٍ،
///     حتى ينتبه الموظف إن نسي زبونًا يلعب. لا يوقف اللعب ولا يغيّر الحساب.
///     الوقت المحدد لا يُذكَّر به دوريًا؛ له تنبيه واحد عند انتهاء وقته، وعندها
///     يتوقف المؤقت وينتهي اللعب تلقائيًا، مع زر "تمديد".
///  2) تذكير قبل موعد كل حجز قادم بساعة، مع زر "تحويل إلى فاتورة".
class RemindersHost extends StatefulWidget {
  final Widget child;
  const RemindersHost({super.key, required this.child});

  @override
  State<RemindersHost> createState() => _RemindersHostState();
}

class _RemindersHostState extends State<RemindersHost> {
  late final InvoicesCubit _invoices;
  late final SettingsCubit _settings;
  late final BookingsCubit _bookings;
  Timer? _timer;

  /// آخر "محطة" تم التنبيه عندها لكل خط لعب (محطة = عدد الفواصل الزمنية المنقضية).
  final Map<int, int> _lastMilestone = {};

  /// الفاصل المستخدم في الفحص السابق. إن غيّره المدير نعيد ضبط المحطات بصمت،
  /// حتى لا يظهر تنبيه فوري خاطئ لمجرد تبديل (ربع ساعة ← ساعة) مثلًا.
  int? _lastInterval;
  final Set<int> _bookingHandled = {};

  @override
  void initState() {
    super.initState();
    _invoices = context.read<InvoicesCubit>();
    _settings = context.read<SettingsCubit>();
    _bookings = context.read<BookingsCubit>();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkExpired();
      _checkPlay();
      _checkBookings();
    });
  }

  // ------------------------------------------------------------ تذكير اللعب

  void _checkPlay() {
    if (_invoices.state.isLoading || !_settings.state.isLoaded) return;
    final interval = _settings.state.settings.reminderIntervalMinutes;
    final now = DateTime.now();

    if (_lastInterval != interval) {
      _lastInterval = interval;
      _lastMilestone.clear();
    }

    final liveIds = <int>{};
    final due = <_DueReminder>[];

    for (final invoice in _invoices.state.open) {
      for (final line in invoice.runningLines) {
        liveIds.add(line.id);
        // الوقت المحدد: بلا تذكير دوري (له تنبيه انتهاء مستقل).
        if (line.isFixed) continue;
        if (interval <= 0) continue;
        final elapsed = line.elapsedAt(now);
        final milestone = elapsed.inMinutes ~/ interval;
        final previous = _lastMilestone[line.id];

        if (previous == null) {
          // أول مرة نرى هذا اللعب (مثلًا بعد إعادة تشغيل التطبيق): لا نزعج
          // الموظف بتنبيه متأخر، نسجّل المحطة الحالية فقط.
          _lastMilestone[line.id] = milestone;
          continue;
        }
        if (milestone > previous && milestone >= 1) {
          _lastMilestone[line.id] = milestone;
          due.add(_DueReminder(
            invoiceId: invoice.id,
            customer: invoice.customerName,
            device: line.resourceName,
            elapsed: elapsed,
            lineId: line.id,
          ));
        }
      }
    }

    // تنظيف الخطوط التي انتهت (ونُخفي تنبيهها إن بقي ظاهرًا).
    final finished = _lastMilestone.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in finished) {
      _lastMilestone.remove(id);
      AlertCenter.instance.dismiss('play-$id');
    }

    if (due.isEmpty) return;
    AlertNotifier.instance.playChime();
    for (final d in due) {
      final title = 'لعب جارٍ — ${d.customer}';
      final body = '${d.device} • مرّ ${describeMinutes(d.elapsed.inMinutes)}';
      AlertNotifier.instance.showToast(title: title, body: body);
      final alertId = 'play-${d.lineId}';
      AlertCenter.instance.show(AppAlert(
        id: alertId,
        icon: Icons.timer_rounded,
        color: AppColors.secondary,
        title: title,
        body: body,
        actionLabel: 'فتح الفاتورة',
        onAction: () async {
          AlertCenter.instance.dismiss(alertId);
          _openInvoice(d.invoiceId);
        },
      ));
    }
  }

  // ------------------------------------------------------- انتهاء الوقت المحدد

  bool _expiring = false;

  /// ينهي الأوقات المحددة المنتهية (تُنهى عند نهايتها بالضبط، حتى لو كان
  /// التطبيق مخفيًا أو أُعيد تشغيله لاحقًا) وينبّه الموظف.
  Future<void> _checkExpired() async {
    if (_expiring || _invoices.state.isLoading) return;
    _expiring = true;
    try {
      final ended = await _invoices.endExpiredFixedLines();
      if (ended.isEmpty) return;
      AlertNotifier.instance.playChime();
      for (final line in ended) {
        _showExpired(line);
      }
    } catch (_) {
      // محاولة أخرى بعد 5 ثوانٍ.
    } finally {
      _expiring = false;
    }
  }

  void _showExpired(PlayLine line) {
    final customer = _invoices.state.openById(line.invoiceId)?.customerName ?? '';
    final title = customer.isEmpty ? 'انتهى الوقت المحدد' : 'انتهى الوقت — $customer';
    final body = '${line.resourceName} • الوقت المحدد ${describeMinutes(line.plannedMinutes ?? 0)}';
    final id = 'expired-${line.id}';

    AlertNotifier.instance.showToast(title: title, body: body);
    AlertCenter.instance.show(AppAlert(
      id: id,
      icon: Icons.timer_off_rounded,
      color: AppColors.danger,
      title: title,
      body: body,
      actionLabel: 'تمديد 15 دقيقة',
      onAction: () async {
        try {
          await _invoices.extendPlay(line.id, 15);
          AlertCenter.instance.dismiss(id);
        } catch (e) {
          AlertCenter.instance.show(AppAlert(
            id: '$id-err',
            icon: Icons.error_outline_rounded,
            color: AppColors.danger,
            title: 'تعذّر التمديد',
            body: e is StateError ? e.message : e.toString(),
          ));
        }
      },
      secondaryLabel: 'فتح الفاتورة',
      onSecondary: () async {
        AlertCenter.instance.dismiss(id);
        _openInvoice(line.invoiceId);
      },
    ));
  }

  void _openInvoice(int invoiceId) {
    final navigator = WindowService.instance.navigatorKey.currentState;
    navigator?.push(MaterialPageRoute(
      builder: (_) => InvoiceDetailPage(invoiceId: invoiceId),
    ));
  }

  // ----------------------------------------------------------- تذكير الحجوزات

  void _checkBookings() {
    if (_bookings.state.isLoading) return;
    final now = DateTime.now();
    final due = findBookingsDueForReminder(_bookings.state.bookings, now)
        .where((b) => !_bookingHandled.contains(b.id))
        .toList();
    if (due.isEmpty) return;

    for (final b in due) {
      _bookingHandled.add(b.id);
      _bookings.markReminderShown(b.id);
      _showBooking(b, now);
    }
    AlertNotifier.instance.playChime();
  }

  void _showBooking(Booking b, DateTime now) {
    final minutes = b.startAt.difference(now).inMinutes;
    final title = minutes > 0 ? 'حجز بعد $minutes دقيقة' : 'حان موعد الحجز';
    final body =
        '${b.customerName} — ${b.resourceName}\n${b.timeRangeLabel}${b.phone.isEmpty ? '' : '  •  ${b.phone}'}';
    final id = 'booking-${b.id}';

    AlertNotifier.instance.showToast(title: title, body: body);
    AlertCenter.instance.show(AppAlert(
      id: id,
      icon: Icons.event_available_rounded,
      color: AppColors.warning,
      title: title,
      body: body,
      actionLabel: 'بدء اللعب الآن',
      onAction: () => _convert(b, id),
    ));
  }

  Future<void> _convert(Booking b, String alertId) async {
    try {
      final invoiceId = await _bookings.convertToInvoice(b.id);
      AlertCenter.instance.dismiss(alertId);
      _openInvoice(invoiceId);
    } catch (e) {
      AlertCenter.instance.show(AppAlert(
        id: '$alertId-err',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
        title: 'تعذّر بدء الحجز',
        body: e is StateError ? e.message : e.toString(),
      ));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DueReminder {
  final int invoiceId;
  final int lineId;
  final String customer;
  final String device;
  final Duration elapsed;
  const _DueReminder({
    required this.invoiceId,
    required this.lineId,
    required this.customer,
    required this.device,
    required this.elapsed,
  });
}
