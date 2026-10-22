import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_info.dart';
import '../theme/app_colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_styles.dart';
import '../widgets/snackbars.dart';
import 'license_service.dart';

/// شاشة التفعيل: تعرض كود الجهاز (يُرسَل للدعم الفني) وتسمح باختيار ملف
/// الترخيص مباشرة بدل نسخه يدويًا.
class LicenseLockPage extends StatefulWidget {
  final LicenseCheckResult result;
  final String licenseFilePath;

  /// يُستدعى بعد تثبيت ملف ترخيص صالح لإعادة تشغيل التهيئة دون إغلاق التطبيق.
  final VoidCallback onActivated;

  const LicenseLockPage({
    super.key,
    required this.result,
    required this.licenseFilePath,
    required this.onActivated,
  });

  @override
  State<LicenseLockPage> createState() => _LicenseLockPageState();
}

class _LicenseLockPageState extends State<LicenseLockPage> {
  bool _busy = false;
  String? _error;

  String get _message {
    switch (widget.result.status) {
      case LicenseStatus.missingLicenseFile:
        return 'هذا الجهاز لم يُفعَّل بعد. أرسل "كود الجهاز" إلى الدعم الفني '
            'للحصول على ملف التفعيل، ثم اخترْه من الزر أدناه.';
      case LicenseStatus.fingerprintMismatch:
        return 'ملف التفعيل الموجود خاص بجهاز آخر. أرسل "كود الجهاز" إلى الدعم '
            'الفني للحصول على ملف جديد لهذا الجهاز.';
      case LicenseStatus.corruptLicenseFile:
        return 'ملف التفعيل تالف أو غير صالح. أرسل "كود الجهاز" إلى الدعم الفني '
            'للحصول على ملف جديد.';
      case LicenseStatus.fingerprintUnavailable:
        return 'تعذّر قراءة معرّف هذا الجهاز من ويندوز. أعد تشغيل التطبيق، '
            'وإن استمرت المشكلة تواصل مع الدعم الفني.';
      case LicenseStatus.valid:
        return '';
    }
  }

  Future<void> _pickLicense() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: 'اختر ملف التفعيل (license.lic)',
        type: FileType.custom,
        allowedExtensions: ['lic'],
      );
      final path = picked?.path;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      final check = await LicenseService.installFrom(path);
      if (!mounted) return;
      if (check.isValid) {
        widget.onActivated();
      } else {
        setState(() {
          _busy = false;
          _error = check.status == LicenseStatus.fingerprintMismatch
              ? 'هذا الملف خاص بجهاز آخر.'
              : 'الملف غير صالح. تأكد أنه الملف الذي أرسله لك الدعم الفني.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذّر قراءة الملف: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fingerprint = widget.result.currentDeviceFingerprint;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.1,
            colors: [AppColors.isDark ? const Color(0xFF1B1646) : const Color(0xFFE3E6FB), AppColors.background],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dimensions.spaceL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(Icons.lock_rounded, size: 42, color: Colors.white),
                  ),
                  const SizedBox(height: Dimensions.spaceL),
                  Text(AppInfo.englishName, style: AppTextStyles.display()),
                  const SizedBox(height: Dimensions.spaceXS),
                  Text('التطبيق غير مُفعَّل', style: AppTextStyles.heading2(AppColors.warning)),
                  const SizedBox(height: Dimensions.spaceS),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge(AppColors.textSecondary),
                  ),
                  const SizedBox(height: Dimensions.spaceL),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Dimensions.spaceM),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Dimensions.radiusL),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        Text('كود الجهاز', style: AppTextStyles.label()),
                        const SizedBox(height: Dimensions.spaceXS),
                        SelectableText(
                          fingerprint,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.timer(AppColors.secondary, 22),
                        ),
                        const SizedBox(height: Dimensions.spaceS),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: fingerprint));
                            showAppSnack(context, 'تم نسخ كود الجهاز');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('نسخ الكود'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceL),
                  SizedBox(
                    width: double.infinity,
                    height: Dimensions.buttonHeightLarge,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _pickLicense,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.upload_file_rounded),
                      label: const Text('اختيار ملف التفعيل'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Dimensions.spaceS),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium(AppColors.danger)),
                  ],
                  const SizedBox(height: Dimensions.spaceM),
                  Text(
                    'أو ضع الملف يدويًا في:\n${widget.licenseFilePath}',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.bodySmall(AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
