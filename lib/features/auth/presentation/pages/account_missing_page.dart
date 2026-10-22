import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/backup/backup_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/snackbars.dart';

/// تظهر عندما كان للجهاز حساب مدير ثم اختفت بياناته (حذف الملف مثلًا).
/// لا نسمح بإنشاء حساب مدير جديد بصمت، لأن هذا يتيح لأي موظف الاستيلاء على
/// صلاحيات المدير بحذف الملف. الحل: استعادة نسخة احتياطية.
class AccountMissingPage extends StatefulWidget {
  const AccountMissingPage({super.key});

  @override
  State<AccountMissingPage> createState() => _AccountMissingPageState();
}

class _AccountMissingPageState extends State<AccountMissingPage> {
  bool _busy = false;

  Future<void> _restore() async {
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
      builder: (ctx) => AlertDialog(
        title: const Text('تمت الاستعادة'),
        content: const Text('أغلق التطبيق ثم افتحه من جديد.'),
        actions: [
          FilledButton(onPressed: () => exit(0), child: const Text('إغلاق التطبيق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(Dimensions.spaceL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 64, color: AppColors.warning),
                const SizedBox(height: Dimensions.spaceM),
                Text('تعذّر العثور على بيانات التطبيق', style: AppTextStyles.heading1()),
                const SizedBox(height: Dimensions.spaceS),
                Text(
                  'كان لهذا الجهاز حساب مدير، لكن ملف البيانات غير موجود الآن '
                  '(ربما حُذف أو نُقل). لحماية الصالة لا يمكن إنشاء حساب مدير جديد '
                  'تلقائيًا.\n\nاستعد آخر نسخة احتياطية من فلاشة أو من مجلد النسخ، '
                  'وإن لم تكن لديك نسخة فتواصل مع الدعم الفني.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge(AppColors.textSecondary),
                ),
                const SizedBox(height: Dimensions.spaceL),
                FilledButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('استعادة نسخة احتياطية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
