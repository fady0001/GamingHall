import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/backup/backup_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/snackbars.dart';

/// النسخ الاحتياطي والأرشفة والاستعادة. النسخ التلقائي يعمل كل 24 ساعة في مجلد
/// المستندات، والأرشفة التلقائية كل شهر، ويمكن للمدير أخذ نسخة أو أرشيف يدويًا.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key});

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  DateTime? _last;
  DateTime? _lastArchive;
  String? _folder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = context.read<BackupService>();
    final last = await service.lastBackupTime();
    final folder = (await service.activeBackupDirectory()).path;
    final archive = await service.lastArchiveTime();
    if (mounted) setState(() {
      _last = last;
      _lastArchive = archive;
      _folder = folder;
    });
  }

  Future<void> _backupDefault() async {
    setState(() => _busy = true);
    final result = await context
        .read<BackupService>()
        .runBackup(trigger: BackupTrigger.manual);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(result);
    _refresh();
  }

  Future<void> _archiveNow() async {
    setState(() => _busy = true);
    final result = await context.read<BackupService>().archiveNow();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.success) {
      showAppSnack(context, 'تمت الأرشفة: ${result.filePath}');
    } else {
      showAppSnack(context, result.errorMessage ?? 'فشلت الأرشفة', error: true);
    }
    _refresh();
  }

  Future<void> _chooseAutoFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مجلد النسخ الاحتياطي التلقائي (يُفضّل فلاشة أو قرص آخر)',
    );
    if (folder == null || !mounted) return;
    try {
      await context.read<BackupService>().setBackupFolder(folder);
      if (mounted) showAppSnack(context, 'تم حفظ مجلد النسخ الاحتياطي.');
    } catch (e) {
      if (mounted) showAppSnack(context, 'تعذّر استخدام هذا المجلد: $e', error: true);
    }
    _refresh();
  }

  Future<void> _backupToFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'اختر مكان حفظ النسخة الاحتياطية (مثلًا فلاشة)',
    );
    if (folder == null || !mounted) return;
    setState(() => _busy = true);
    final result = await context
        .read<BackupService>()
        .runBackup(trigger: BackupTrigger.manual, folderPath: folder);
    if (!mounted) return;
    setState(() => _busy = false);
    _report(result);
    _refresh();
  }

  void _report(BackupResult result) {
    if (result.success) {
      showAppSnack(context, 'تم حفظ النسخة الاحتياطية في: ${result.filePath}');
    } else {
      showAppSnack(context, result.errorMessage ?? 'فشل النسخ الاحتياطي', error: true);
    }
  }

  Future<void> _restore() async {
    final ok = await showConfirmDialog(
      context,
      title: 'استعادة نسخة احتياطية؟',
      message: 'ستُستبدل كل البيانات الحالية (فواتير، أسعار، حجوزات...) بمحتوى '
          'النسخة المختارة، ثم يُغلق التطبيق لتفتحه من جديد. تُحفظ نسخة أمان من '
          'بياناتك الحالية بجانب الملف الأصلي.',
      confirmLabel: 'متابعة',
      danger: true,
    );
    if (!ok || !mounted) return;

    final picked = await FilePicker.pickFile(
      dialogTitle: 'اختر ملف النسخة الاحتياطية (.db)',
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;

    setState(() => _busy = true);
    final result = await context.read<BackupService>().restoreFrom(path);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      showAppSnack(context, result.errorMessage ?? 'فشلت الاستعادة', error: true);
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        title: 'تمت الاستعادة',
        icon: Icons.check_circle_rounded,
        iconColor: AppColors.success,
        actions: [
          FilledButton(
            onPressed: () => exit(0),
            child: const Text('إغلاق التطبيق'),
          ),
        ],
        child: Text('تمت استعادة البيانات. أغلق التطبيق ثم افتحه من جديد.',
            style: AppTextStyles.bodyLarge(AppColors.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _last == null
              ? 'لم تُؤخذ أي نسخة احتياطية بعد.'
              : 'آخر نسخة احتياطية: ${formatDateTime(_last!)}',
          style: AppTextStyles.bodyLarge(),
        ),
        const SizedBox(height: 4),
        Text(
          'يُؤخذ نسخ تلقائي كل 24 ساعة ويُحتفظ بآخر 30 نسخة في:\n${_folder ?? '...'}',
          textDirection: TextDirection.ltr,
          style: AppTextStyles.bodySmall(),
        ),
        const SizedBox(height: Dimensions.spaceS),
        Text(
          _lastArchive == null
              ? 'الأرشيف: لم تتم أي أرشفة بعد.'
              : 'آخر أرشفة: ${formatDateTime(_lastArchive!)}',
          style: AppTextStyles.bodyLarge(),
        ),
        const SizedBox(height: 4),
        Text(
          'تُحفظ نسخة أرشيف كاملة تلقائيًا كل شهر في مجلد Archive داخل مجلد النسخ، ولا تُحذف أبدًا.',
          style: AppTextStyles.bodySmall(),
        ),
        const SizedBox(height: Dimensions.spaceM),
        Wrap(
          spacing: Dimensions.spaceS,
          runSpacing: Dimensions.spaceS,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _backupDefault,
              icon: const Icon(Icons.backup_rounded),
              label: const Text('نسخة احتياطية الآن'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseAutoFolder,
              icon: const Icon(Icons.folder_special_rounded),
              label: const Text('تغيير مجلد النسخ التلقائي'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _backupToFolder,
              icon: const Icon(Icons.usb_rounded),
              label: const Text('نسخ إلى مجلد أو فلاشة'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _archiveNow,
              icon: const Icon(Icons.inventory_2_rounded),
              label: const Text('أرشفة الآن'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('استعادة من نسخة'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
          ],
        ),
      ],
    );
  }
}
