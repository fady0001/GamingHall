import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/snackbars.dart';

/// يعرض رمز الاسترداد مرة واحدة. لا يُغلق إلا بعد تأكيد المستخدم أنه حفظه،
/// لأن الرمز لا يُخزَّن بشكل قابل للقراءة ولا يمكن عرضه مرة أخرى.
Future<void> showRecoveryCodeDialog(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RecoveryCodeDialog(code: code),
  );
}

class _RecoveryCodeDialog extends StatefulWidget {
  final String code;
  const _RecoveryCodeDialog({required this.code});

  @override
  State<_RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<_RecoveryCodeDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AppDialog(
        title: 'رمز استرداد حساب المدير',
        icon: Icons.key_rounded,
        iconColor: AppColors.warning,
        width: 500,
        actions: [
          FilledButton(
            onPressed: _saved ? () => Navigator.of(context).pop() : null,
            child: const Text('تم، متابعة'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'إذا نسيت كلمة سر المدير فهذا الرمز هو الطريقة الوحيدة لاستردادها. '
              'اكتبه على ورقة واحفظه في مكان آمن بعيدًا عن الموظفين. '
              'لن يظهر مرة أخرى.',
              style: AppTextStyles.bodyLarge(AppColors.textSecondary),
            ),
            const SizedBox(height: Dimensions.spaceM),
            Container(
              padding: const EdgeInsets.all(Dimensions.spaceM),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(Dimensions.radiusM),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
              ),
              child: Column(
                children: [
                  SelectableText(
                    widget.code,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.timer(AppColors.warning, 26),
                  ),
                  const SizedBox(height: Dimensions.spaceS),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.code));
                      showAppSnack(context, 'تم نسخ الرمز');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('نسخ الرمز'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Dimensions.spaceS),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              title: Text('حفظت الرمز في مكان آمن',
                  style: AppTextStyles.bodyLarge()),
            ),
          ],
        ),
      ),
    );
  }
}
