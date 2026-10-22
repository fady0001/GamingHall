import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/usecases/billing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../bookings/domain/entities/booking.dart';
import '../../../resources/domain/entities/resource_kind.dart';
import '../../../resources/domain/entities/resource_status.dart';
import '../../../resources/domain/usecases/build_resource_views.dart';
import '../../../resources/presentation/cubit/devices_board_cubit.dart';
import '../cubit/invoices_cubit.dart';

/// بدء لعب: وقت مفتوح (يوقفه الموظف) أو وقت محدد (ينتهي تلقائيًا مع تنبيه
/// وزر تمديد). يعمل بثلاث طرق:
///  - [fixedResourceId]: من بطاقة جهاز (يختار الموظف الفاتورة وعدد اللاعبين).
///  - [fixedInvoiceId]: من داخل فاتورة (يختار الجهاز وعدد اللاعبين).
///  - بدون الاثنين: يختار الجهاز والفاتورة معًا.
/// يعيد معرّف الفاتورة عند النجاح.
Future<int?> showStartPlayDialog(
  BuildContext context, {
  int? fixedResourceId,
  int? fixedInvoiceId,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _StartPlayDialog(
      fixedResourceId: fixedResourceId,
      fixedInvoiceId: fixedInvoiceId,
    ),
  );
}

class _StartPlayDialog extends StatefulWidget {
  final int? fixedResourceId;
  final int? fixedInvoiceId;
  const _StartPlayDialog({this.fixedResourceId, this.fixedInvoiceId});

  @override
  State<_StartPlayDialog> createState() => _StartPlayDialogState();
}

class _StartPlayDialogState extends State<_StartPlayDialog> {
  int? _resourceId;
  int _players = 1;
  bool _newInvoice = true;
  int? _invoiceId;
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  /// false = وقت مفتوح، true = وقت محدد بمدة يكتبها الموظف.
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
    _resourceId = widget.fixedResourceId;
    final open = context.read<InvoicesCubit>().state.open;
    // إن وُجدت فواتير مفتوحة نقترح "فاتورة موجودة" فقط عند الطلب؛ الأشيع زبون جديد.
    _newInvoice = widget.fixedInvoiceId == null;
    if (widget.fixedInvoiceId == null && open.isNotEmpty) _invoiceId = open.first.id;
  }

  @override
  void dispose() {
    _hours.dispose();
    _mins.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit(ResourceView? view) async {
    if (view == null) {
      setState(() => _error = 'اختر الجهاز أو الطاولة');
      return;
    }
    final cubit = context.read<InvoicesCubit>();
    final invoiceFixed = widget.fixedInvoiceId;

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

    if (invoiceFixed == null && _newInvoice && _name.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم الزبون');
      return;
    }
    if (invoiceFixed == null && !_newInvoice && _invoiceId == null) {
      setState(() => _error = 'اختر الفاتورة');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    int? createdInvoiceId;
    try {
      int invoiceId;
      if (invoiceFixed != null) {
        invoiceId = invoiceFixed;
      } else if (_newInvoice) {
        final invoice = await cubit.create(_name.text);
        createdInvoiceId = invoice.id;
        invoiceId = invoice.id;
      } else {
        invoiceId = _invoiceId!;
      }
      await cubit.startPlay(
        invoiceId: invoiceId,
        resourceId: view.resource.id,
        playerCount: _players.clamp(1, view.resource.maxPlayers),
        plannedMinutes: _fixed ? _plannedMinutes : null,
      );
      if (mounted) Navigator.of(context).pop(invoiceId);
    } catch (e) {
      // لا نترك فاتورة فارغة أنشأناها للتو إن فشل بدء اللعب.
      if (createdInvoiceId != null) {
        try {
          await cubit.deleteIfEmpty(createdInvoiceId);
        } catch (_) {}
      }
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
    final views = context.watch<DevicesBoardCubit>().state.views;
    final openInvoices = context.watch<InvoicesCubit>().state.open;

    ResourceView? selected;
    for (final v in views) {
      if (v.resource.id == _resourceId) selected = v;
    }

    final selectable = views
        .where((v) =>
            v.status == ResourceStatus.available ||
            v.status == ResourceStatus.reserved)
        .toList();

    // لو أصبح الجهاز المختار غير متاح (شغّله أحد للتو) ننبّه.
    final selectedUnavailable = selected != null &&
        selected.status != ResourceStatus.available &&
        selected.status != ResourceStatus.reserved;

    final maxPlayers = selected?.resource.maxPlayers ?? 4;
    final players = _players.clamp(1, maxPlayers);

    return AppDialog(
      title: 'بدء لعب',
      icon: Icons.play_circle_rounded,
      iconColor: AppColors.statusAvailable,
      width: 620,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: (_busy || selectedUnavailable) ? null : () => _submit(selected),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_fixed ? 'ابدأ الوقت المحدد' : 'ابدأ الوقت الآن'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----- الجهاز
          Text('الجهاز', style: AppTextStyles.label()),
          const SizedBox(height: 8),
          if (widget.fixedResourceId != null && selected != null)
            _SelectedDeviceTile(view: selected)
          else if (selectable.isEmpty)
            Text('لا توجد أجهزة متاحة الآن.',
                style: AppTextStyles.bodyMedium(AppColors.warning))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in selectable)
                  ChoiceChip(
                    selected: v.resource.id == _resourceId,
                    avatar: Icon(v.resource.icon, size: 18),
                    label: Text(v.resource.name),
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                              _resourceId = v.resource.id;
                              _players = _players.clamp(1, v.resource.maxPlayers);
                              _error = null;
                            }),
                  ),
              ],
            ),
          if (selected?.status == ResourceStatus.reserved &&
              selected?.upcomingBooking != null) ...[
            const SizedBox(height: 8),
            _ReservedWarning(booking: selected!.upcomingBooking!),
          ],
          if (selectedUnavailable) ...[
            const SizedBox(height: 8),
            Text('هذا الجهاز لم يعد متاحًا. اخترْ جهازًا آخر.',
                style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],

          // ----- عدد اللاعبين (شاشات البلايستيشن فقط)
          if (selected != null && selected.resource.kind.hasPlayerPricing) ...[
            const SizedBox(height: Dimensions.spaceL),
            Text('عدد اللاعبين', style: AppTextStyles.label()),
            const SizedBox(height: 8),
            // Wrap بدل Row: إن ضاقت النافذة نزل السعر تحت الأزرار بدل overflow.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Dimensions.spaceM,
              runSpacing: 8,
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var i = 1; i <= selected.resource.maxPlayers; i++)
                      ButtonSegment(value: i, label: Text('$i')),
                  ],
                  selected: {players},
                  onSelectionChanged:
                      _busy ? null : (s) => setState(() => _players = s.first),
                ),
                Text(
                  'السعر: ${formatMoneyWithUnit(selected.resource.rateFor(players))} / ساعة',
                  style: AppTextStyles.price(AppColors.secondary, 16),
                ),
              ],
            ),
          ] else if (selected != null) ...[
            const SizedBox(height: Dimensions.spaceM),
            Text(
              'السعر: ${formatMoneyWithUnit(selected.resource.rateFor(1))} / ساعة',
              style: AppTextStyles.price(AppColors.secondary, 16),
            ),
          ],

          // ----- نوع الوقت
          if (selected != null) ...[
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
                    value: true,
                    icon: Icon(Icons.timer_rounded),
                    label: Text('وقت محدد')),
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
              Text('يبدأ المؤقت الآن ويستمر حتى توقفه أنت، ويُحسب لأقرب دقيقة.',
                  style: AppTextStyles.bodySmall())
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
                    Text(
                      '${describeMinutes(_plannedMinutes)} • ≈ ${formatMoneyWithUnit(chargeForMinutes(hourlyRate: selected.resource.rateFor(players), minutes: _plannedMinutes))}',
                      style: AppTextStyles.price(AppColors.secondary, 15),
                    ),
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
              const SizedBox(height: 4),
              Text(
                'عند انتهاء الوقت يتوقف المؤقت وتظهر لك نافذة تنبيه مع زر "تمديد". '
                'وإن غادر الزبون قبل ذلك أوقف الوقت وتُحسب دقائقه الفعلية فقط.',
                style: AppTextStyles.bodySmall(),
              ),
            ],
          ],

          // ----- الفاتورة
          if (widget.fixedInvoiceId == null) ...[
            const SizedBox(height: Dimensions.spaceL),
            Text('الفاتورة', style: AppTextStyles.label()),
            const SizedBox(height: 8),
            if (openInvoices.isNotEmpty)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('زبون جديد')),
                  ButtonSegment(value: false, label: Text('فاتورة مفتوحة')),
                ],
                selected: {_newInvoice},
                onSelectionChanged:
                    _busy ? null : (s) => setState(() => _newInvoice = s.first),
              ),
            const SizedBox(height: 10),
            if (_newInvoice || openInvoices.isEmpty)
              TextField(
                controller: _name,
                enabled: !_busy,
                maxLength: 60,
                autofocus: widget.fixedResourceId != null,
                onSubmitted: (_) => _submit(selected),
                decoration: const InputDecoration(
                  labelText: 'اسم الزبون',
                  prefixIcon: Icon(Icons.person_rounded),
                  counterText: '',
                ),
              )
            else
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: openInvoices.any((i) => i.id == _invoiceId)
                    ? _invoiceId
                    : openInvoices.first.id,
                decoration: const InputDecoration(
                  labelText: 'اختر الفاتورة',
                  prefixIcon: Icon(Icons.receipt_long_rounded),
                ),
                items: [
                  for (final i in openInvoices)
                    DropdownMenuItem(
                      value: i.id,
                      child: Text('#${i.id}  ${i.customerName}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _invoiceId = v),
              ),
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
                      child: Text(_error!,
                          style: AppTextStyles.bodyMedium(AppColors.danger))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedDeviceTile extends StatelessWidget {
  final ResourceView view;
  const _SelectedDeviceTile({required this.view});

  @override
  Widget build(BuildContext context) {
    final r = view.resource;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(r.icon, color: AppColors.primaryLight),
          const SizedBox(width: 10),
          Flexible(
            child: Text(r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading3()),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(r.typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall()),
          ),
        ],
      ),
    );
  }
}

class _ReservedWarning extends StatelessWidget {
  final Booking booking;
  const _ReservedWarning({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bookmark_rounded, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'تنبيه: الجهاز محجوز لـ ${booking.customerName} '
              '(${booking.timeRangeLabel}). '
              'لا يمكن بدء لعب يتداخل مع وقت الحجز؛ اختر "وقت محدد" ينتهي قبل موعده.',
              style: AppTextStyles.bodyMedium(AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}
