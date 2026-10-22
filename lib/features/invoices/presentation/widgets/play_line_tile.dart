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
import '../../../../core/widgets/live_builder.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../domain/entities/invoice.dart';
import '../cubit/invoices_cubit.dart';
import '../../../resources/domain/entities/resource_kind.dart';

/// بطاقة خط لعب: عدّاد حيّ وأجر حيّ وزر إيقاف (للعب الجاري).
class PlayLineTile extends StatelessWidget {
  final PlayLine line;
  final bool editable;
  const PlayLineTile({super.key, required this.line, required this.editable});

  Future<void> _stop(BuildContext context) async {
    final cubit = context.read<InvoicesCubit>();
    final now = DateTime.now();
    final minutes = line.minutesAt(now);
    final cost = line.chargeAt(now);
    final ok = await showConfirmDialog(
      context,
      title: 'إيقاف الوقت؟',
      message: 'سيتوقف العدّاد على "${line.resourceName}" بعد '
          '${describeMinutes(minutes)} وأجره ${formatMoneyWithUnit(cost)}. '
          'لا يمكن استئنافه بعد الإيقاف.',
      confirmLabel: 'إيقاف الوقت',
      icon: Icons.stop_circle_rounded,
    );
    if (!ok) return;
    try {
      await cubit.stopPlay(line.id);
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _extend(BuildContext context) async {
    final cubit = context.read<InvoicesCubit>();
    final minutes = await showExtendDialog(context);
    if (minutes == null) return;
    try {
      await cubit.extendPlay(line.id, minutes);
      if (context.mounted) {
        showAppSnack(context, 'تم تمديد الوقت ${describeMinutes(minutes)}');
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = line.isRunning;
    final accent = running ? AppColors.statusBusy : AppColors.border;

    final iconBox = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: (running ? AppColors.statusBusy : AppColors.textMuted)
            .withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
      ),
      child: Icon(
        iconForTypeName(line.typeKey, line.resourceKind),
        color: running ? AppColors.statusBusy : AppColors.textSecondary,
      ),
    );

    // الاسم + شارة الوقت المحدد في Wrap حتى لا يتجاوز الصف عرض البطاقة.
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(line.resourceName, style: AppTextStyles.heading3()),
            if (line.isFixed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('وقت محدد ${describeMinutes(line.plannedMinutes!)}',
                    style: AppTextStyles.bodySmall(AppColors.secondary)),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${line.resourceKind == ResourceKind.playstation ? '${line.playerCount} ${line.playerCount == 1 ? 'لاعب' : 'لاعبين'}  •  ' : ''}'
          '${formatMoney(line.hourlyRate)} ل.س / ساعة'
          '  •  بدأ ${formatClock(line.startedAt)}'
          '${running ? '' : ' وانتهى ${formatClock(line.endedAt!)}'}',
          style: AppTextStyles.bodySmall(),
        ),
      ],
    );

    Widget figures(CrossAxisAlignment align) {
      if (running) {
        return LiveBuilder(
          builder: (context, now) => Column(
            crossAxisAlignment: align,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (line.isFixed)
                Text('المتبقي ${formatDuration(line.remainingAt(now)!)}',
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.timer(
                        (line.remainingAt(now)!.inMinutes < 5)
                            ? AppColors.warning
                            : AppColors.secondary,
                        24))
              else
                Text(formatDuration(line.elapsedAt(now)),
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.timer(AppColors.secondary, 26)),
              if (line.isFixed)
                Text('مضى ${formatDuration(line.elapsedAt(now))}',
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.bodySmall()),
              Text(formatMoneyWithUnit(line.chargeAt(now)),
                  style: AppTextStyles.price(AppColors.textPrimary, 15)),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(describeMinutes(line.billedMinutes ?? 0),
              style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
          Text(formatMoneyWithUnit(line.charge!),
              style: AppTextStyles.price(AppColors.textPrimary, 18)),
        ],
      );
    }

    final extendButton = (line.isFixed && editable)
        ? OutlinedButton.icon(
            onPressed: () => _extend(context),
            icon: const Icon(Icons.more_time_rounded),
            label: const Text('تمديد'),
          )
        : null;
    final stopButton = (running && editable)
        ? FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => _stop(context),
            icon: const Icon(Icons.stop_rounded),
            label: const Text('إيقاف'),
          )
        : null;

    return AppCard(
      accentColor: running ? accent : null,
      glow: running,
      padding: const EdgeInsets.all(Dimensions.spaceM),
      child: LayoutBuilder(
        builder: (context, c) {
          // بطاقة ضيقة (نافذة صغيرة / هاتف): كل شيء عموديًا بدل صف واحد
          // يتجاوز العرض (العدّاد + زر التمديد + زر الإيقاف).
          if (c.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(width: Dimensions.spaceM),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: Dimensions.spaceS),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: figures(CrossAxisAlignment.start),
                ),
                if (extendButton != null || stopButton != null) ...[
                  const SizedBox(height: Dimensions.spaceS),
                  Wrap(
                    spacing: Dimensions.spaceS,
                    runSpacing: Dimensions.spaceS,
                    children: [
                      if (extendButton != null) extendButton,
                      if (stopButton != null) stopButton,
                    ],
                  ),
                ],
              ],
            );
          }
          return Row(
            children: [
              iconBox,
              const SizedBox(width: Dimensions.spaceM),
              Expanded(child: info),
              const SizedBox(width: Dimensions.spaceM),
              figures(CrossAxisAlignment.end),
              if (extendButton != null) ...[
                const SizedBox(width: Dimensions.spaceM),
                extendButton,
              ],
              if (stopButton != null) ...[
                const SizedBox(width: Dimensions.spaceS),
                stopButton,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// يسأل عن مدة التمديد (دقائق). يعيد null عند الإلغاء.
Future<int?> showExtendDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    builder: (_) => const _ExtendDialog(),
  );
}

class _ExtendDialog extends StatefulWidget {
  const _ExtendDialog();

  @override
  State<_ExtendDialog> createState() => _ExtendDialogState();
}

class _ExtendDialogState extends State<_ExtendDialog> {
  final _custom = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _submitCustom() {
    final m = int.tryParse(_custom.text.trim()) ?? 0;
    if (m < 1 || m > 24 * 60) {
      setState(() => _error = 'اكتب عدد دقائق صحيحًا');
      return;
    }
    Navigator.of(context).pop(m);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'تمديد الوقت',
      icon: Icons.more_time_rounded,
      width: 440,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كم تريد أن تمدّد؟', style: AppTextStyles.bodyLarge()),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [15, 30, 45, 60, 90])
                ActionChip(
                  label: Text(describeMinutes(m)),
                  onPressed: () => Navigator.of(context).pop(m),
                ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  onSubmitted: (_) => _submitCustom(),
                  decoration: InputDecoration(
                    labelText: 'مدة أخرى بالدقائق',
                    counterText: '',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: Dimensions.buttonHeight,
                child: FilledButton(onPressed: _submitCustom, child: const Text('تمديد')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
