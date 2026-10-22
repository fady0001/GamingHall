import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/friendly_error.dart';
import '../../../core/widgets/snackbars.dart';
import '../../invoices/presentation/cubit/invoices_cubit.dart';
import '../domain/repositories/work_day_repository.dart';
import 'cubit/work_day_cubit.dart';

/// تدفق "يوم عمل جديد": يُستدعى من الشريط الجانبي (يظهر في كل الصفحات).
/// لا يبدأ يوم جديد وفيه فواتير مفتوحة.
Future<void> startNewWorkDayFlow(BuildContext context) async {
  final dayCubit = context.read<WorkDayCubit>();
  final open = context.read<InvoicesCubit>().state.open;

  if (open.isNotEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'لا يمكن بدء يوم عمل جديد الآن',
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.warning,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('حسنًا'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'يوجد ${open.length} فاتورة مفتوحة. حاسِب كل فاتورة أولًا ثم ابدأ يوم عمل جديد، '
              'حتى لا يُحسب لعب أي زبون بشكل خاطئ.',
              style: AppTextStyles.bodyLarge(AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final i in open.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• #${i.id}  ${i.customerName}',
                    style: AppTextStyles.bodyLarge()),
              ),
            if (open.length > 8)
              Text('... و${open.length - 8} أخرى', style: AppTextStyles.bodyMedium()),
          ],
        ),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  final ok = await showConfirmDialog(
    context,
    title: 'بدء يوم عمل جديد؟',
    message: 'سيُغلق يوم العمل الحالي ويُحفظ في السجل، وتبدأ صفحة جديدة فارغة '
        'من الفواتير. لن يُحذف أي شيء.',
    confirmLabel: 'ابدأ يوم عمل جديد',
    icon: Icons.event_repeat_rounded,
  );
  if (!ok || !context.mounted) return;

  try {
    final day = await dayCubit.startNewDay();
    if (context.mounted) showAppSnack(context, 'بدأ يوم عمل جديد: ${day.label}');
  } on OpenInvoicesException catch (e) {
    if (context.mounted) showAppSnack(context, e.toString(), error: true);
  } catch (e) {
    if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
  }
}
