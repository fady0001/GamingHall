import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/debug/demo_data_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../reports/presentation/cubit/reports_cubit.dart';

/// أدوات التجربة (تظهر في نسخة Debug فقط): إضافة/حذف بيانات تجريبية.
class DemoDataSection extends StatefulWidget {
  const DemoDataSection({super.key});

  @override
  State<DemoDataSection> createState() => _DemoDataSectionState();
}

class _DemoDataSectionState extends State<DemoDataSection> {
  bool _busy = false;
  bool _has = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final has = await context.read<DemoDataService>().hasDemoData();
    if (mounted) setState(() => _has = has);
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final msg = await action();
      if (!mounted) return;
      showAppSnack(context, msg);
      context.read<ReportsCubit>().load();
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<DemoDataService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'يضيف أجهزة وأصنافًا تجريبية (تحمل كلمة «تجريبي») مع فواتير وجلسات وحجوزات لآخر 10 أيام. '
          'الحذف يمسح البيانات التجريبية فقط ولا يلمس بياناتك الحقيقية.',
          style: AppTextStyles.bodyMedium(AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy || _has ? null : () => _run(service.seed),
              icon: const Icon(Icons.science_rounded),
              label: const Text('إضافة بيانات تجريبية'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || !_has ? null : () => _run(service.clear),
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('حذف البيانات التجريبية'),
            ),
          ],
        ),
      ],
    );
  }
}
