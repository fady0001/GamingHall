import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../resources/domain/entities/game_resource.dart';
import '../../../resources/domain/entities/resource_kind.dart';
import '../../../resources/presentation/cubit/resources_cubit.dart';
import '../../domain/entities/booking.dart';
import '../../domain/usecases/booking_rules.dart';
import '../cubit/bookings_cubit.dart';

Future<bool> showBookingDialog(BuildContext context, {DateTime? initialDay}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _BookingDialog(initialDay: initialDay),
  );
  return ok ?? false;
}

class _BookingDialog extends StatefulWidget {
  final DateTime? initialDay;
  const _BookingDialog({this.initialDay});

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  int? _resourceId;
  int _players = 1;
  late DateTime _date;
  late TimeOfDay _time;
  bool _busy = false;
  String? _error;

  /// false = وقت مفتوح، true = وقت محدد بمدة (نفس طريقة بدء اللعب).
  bool _fixed = false;
  final _hours = TextEditingController(text: '1');
  final _mins = TextEditingController(text: '0');

  int get _plannedMinutes =>
      (int.tryParse(_hours.text.trim()) ?? 0) * 60 + (int.tryParse(_mins.text.trim()) ?? 0);

  void _setPlanned(int total) {
    _hours.text = '${total ~/ 60}';
    _mins.text = '${total % 60}';
    setState(() => _error = null);
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final base = widget.initialDay ?? now;
    _date = DateTime(base.year, base.month, base.day);
    // أقرب نصف ساعة قادمة.
    final next = now.add(Duration(minutes: 30 - now.minute % 30));
    _time = TimeOfDay(hour: next.hour, minute: next.minute);
    if (widget.initialDay != null &&
        DateTime(base.year, base.month, base.day).isAfter(DateTime(now.year, now.month, now.day))) {
      _time = const TimeOfDay(hour: 18, minute: 0);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _hours.dispose();
    _mins.dispose();
    super.dispose();
  }

  DateTime get _start =>
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  DateTime get _end =>
      _fixed ? _start.add(Duration(minutes: _plannedMinutes)) : _start.add(bookingLead);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(DateTime(now.year, now.month, now.day))
          ? DateTime(now.year, now.month, now.day)
          : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      // نظام 12 ساعة (ص / م) وليس 24 ساعة.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _submit(GameResource? selected) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم الزبون');
      return;
    }
    final phoneError = validateBookingPhone(_phone.text);
    if (phoneError != null) {
      setState(() => _error = phoneError);
      return;
    }
    if (selected == null) {
      setState(() => _error = 'اختر الجهاز أو الطاولة');
      return;
    }
    if (_fixed) {
      final m = _plannedMinutes;
      if (m < 1) {
        setState(() => _error = 'اكتب مدة الوقت المحدد (دقيقة على الأقل)');
        return;
      }
      if (m > 24 * 60) {
        setState(() => _error = 'الوقت المحدد لا يتجاوز 24 ساعة');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<BookingsCubit>().create(
            customerName: _name.text,
            phone: _phone.text,
            resourceId: selected.id,
            // عدد اللاعبين للبلايستيشن فقط؛ غيره دائمًا 1 ولا يُسأل عنه.
            playerCount: selected.kind.hasPlayerPricing
                ? _players.clamp(1, selected.maxPlayers)
                : 1,
            startAt: _start,
            endAt: _end,
            isOpen: !_fixed,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on BookingConflictException catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    } on BookingValidationException catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final resources = context
        .watch<ResourcesCubit>()
        .state
        .resources
        .where((r) => !r.outOfService)
        .toList();

    GameResource? selected;
    for (final r in resources) {
      if (r.id == _resourceId) selected = r;
    }
    final isPs = selected?.kind.hasPlayerPricing ?? false;
    final maxPlayers = selected?.maxPlayers ?? 4;
    if (_players > maxPlayers) _players = maxPlayers;

    return AppDialog(
      title: 'حجز جديد',
      icon: Icons.event_available_rounded,
      iconColor: AppColors.warning,
      width: 560,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _submit(selected),
          icon: const Icon(Icons.check_rounded),
          label: const Text('حفظ الحجز'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveRow(
            first: TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'اسم الزبون',
                prefixIcon: Icon(Icons.person_rounded),
                counterText: '',
              ),
            ),
            second: TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                hintText: '09XXXXXXXX',
                prefixIcon: Icon(Icons.phone_rounded),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          DropdownButtonFormField<int>(
            initialValue: _resourceId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'الجهاز أو الطاولة',
              prefixIcon: Icon(Icons.sports_esports_rounded),
            ),
            items: [
              for (final r in resources)
                DropdownMenuItem(
                  value: r.id,
                  child: Text('${r.name}  (${r.typeLabel})', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _resourceId = v),
          ),
          // ----- عدد اللاعبين: للبلايستيشن فقط (1 إلى 4)
          if (isPs) ...[
            const SizedBox(height: Dimensions.spaceM),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Dimensions.spaceM,
              runSpacing: 8,
              children: [
                Text('عدد اللاعبين', style: AppTextStyles.label()),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 1; i <= maxPlayers; i++)
                      ButtonSegment(value: i, label: Text('$i')),
                  ],
                  selected: {_players},
                  onSelectionChanged: _busy ? null : (s) => setState(() => _players = s.first),
                ),
              ],
            ),
          ],
          const SizedBox(height: Dimensions.spaceM),
          AdaptiveRow(
            first: OutlinedButton.icon(
              onPressed: _busy ? null : _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text('${arabicDayName(_date)} ${formatDate(_date)}',
                  overflow: TextOverflow.ellipsis),
            ),
            second: OutlinedButton.icon(
              onPressed: _busy ? null : _pickTime,
              icon: const Icon(Icons.schedule_rounded),
              label: Text(formatClock(_start), textDirection: TextDirection.rtl),
            ),
          ),

          // ----- نوع الوقت (نفس طريقة بدء اللعب)
          const SizedBox(height: Dimensions.spaceL),
          Text('نوع الوقت', style: AppTextStyles.label()),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.all_inclusive_rounded),
                  label: Text('وقت مفتوح')),
              ButtonSegment(
                  value: true, icon: Icon(Icons.timer_rounded), label: Text('وقت محدد')),
            ],
            selected: {_fixed},
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() {
                      _fixed = s.first;
                      _error = null;
                    }),
          ),
          const SizedBox(height: 8),
          if (!_fixed)
            Text(
              'يبدأ الحجز من ${formatClock(_start)} بدون مدة محددة؛ يُحسب الوقت عند بدء اللعب ويوقفه الموظف.',
              style: AppTextStyles.bodySmall(),
            )
          else ...[
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _hours,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 2,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(labelText: 'ساعات', counterText: ''),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _mins,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 2,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(labelText: 'دقائق', counterText: ''),
                  ),
                ),
                if (_plannedMinutes > 0)
                  Text(describeMinutes(_plannedMinutes),
                      style: AppTextStyles.price(AppColors.secondary, 15)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final m in const [30, 60, 90, 120])
                  ActionChip(
                    label: Text(describeMinutes(m)),
                    onPressed: _busy ? null : () => _setPlanned(m),
                  ),
              ],
            ),
            if (_plannedMinutes > 0) ...[
              const SizedBox(height: 8),
              Text('من ${formatClock(_start)} إلى ${formatClock(_end)}',
                  style: AppTextStyles.bodyMedium(AppColors.secondary)),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceM),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Dimensions.radiusM),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
