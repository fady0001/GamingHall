import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/month_names.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../data/monthly_report_exporter.dart';
import '../../domain/repositories/monthly_report_repository.dart';

/// يختار المدير الشهر، فيُنشأ التقرير PDF ويُحفظ ويُفتح.
/// يعيد مسار الملف عند النجاح، أو null عند الإلغاء.
Future<String?> showMonthlyReportDialog(BuildContext context) {
  final repository = context.read<MonthlyReportRepository>();
  final settingsCubit = context.read<SettingsCubit>();
  return showDialog<String>(
    context: context,
    builder: (_) => _MonthlyReportDialog(
      repository: repository,
      settingsCubit: settingsCubit,
    ),
  );
}

class _MonthlyReportDialog extends StatefulWidget {
  final MonthlyReportRepository repository;
  final SettingsCubit settingsCubit;
  const _MonthlyReportDialog({
    required this.repository,
    required this.settingsCubit,
  });

  @override
  State<_MonthlyReportDialog> createState() => _MonthlyReportDialogState();
}

class _MonthlyReportDialogState extends State<_MonthlyReportDialog> {
  /// الأشهر المتاحة (الأحدث أولًا). فارغة حتى يُحمَّل أول شهر فيه نشاط.
  List<DateTime> _months = const [];
  DateTime? _selected;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMonths();
  }

  Future<void> _loadMonths() async {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 1);
    DateTime first = current;
    try {
      final earliest = await widget.repository.earliestMonth();
      if (earliest != null && earliest.isBefore(current)) first = earliest;
    } catch (_) {}
    final months = <DateTime>[];
    for (var m = current; !m.isBefore(first); m = DateTime(m.year, m.month - 1, 1)) {
      months.add(m);
    }
    if (!mounted) return;
    setState(() {
      _months = months;
      _selected = months.first;
    });
  }

  Future<void> _generate() async {
    final month = _selected;
    if (month == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await widget.repository.build(month.year, month.month);
      final path = await MonthlyReportExporter.save(
        report,
        widget.settingsCubit.state.settings,
      );
      await MonthlyReportExporter.open(path);
      if (mounted) Navigator.of(context).pop(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذّر إنشاء التقرير: ${friendlyError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'التقرير الشهري PDF',
      icon: Icons.picture_as_pdf_rounded,
      width: 480,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: (_busy || _selected == null) ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_busy ? 'جارٍ الإنشاء...' : 'إنشاء وفتح'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('اختر الشهر', style: AppTextStyles.label(AppColors.textSecondary)),
          const SizedBox(height: Dimensions.spaceXS),
          if (_selected == null)
            const Padding(
              padding: EdgeInsets.all(Dimensions.spaceS),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            DropdownButtonFormField<DateTime>(
              initialValue: _selected,
              isExpanded: true,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.event_rounded)),
              items: [
                for (final m in _months)
                  DropdownMenuItem(
                    value: m,
                    child: Text(monthLabel(m.year, m.month)),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _selected = v),
            ),
          const SizedBox(height: Dimensions.spaceM),
          Text(
            'يُحفظ الملف في المستندات ← GamingHall ← Reports ويُفتح تلقائيًا. '
            'إعادة إنشاء نفس الشهر تستبدل الملف السابق.',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceM),
            Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],
        ],
      ),
    );
  }
}
