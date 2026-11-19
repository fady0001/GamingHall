import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../domain/repositories/auth_repository.dart';
import '../cubit/auth_cubit.dart';

/// المدير فقد كلمة السر ورمز الاسترداد معًا.
///
/// 1) يعرض "رمز الطلب" ليرسله للدعم الفني (واتساب مثلًا).
/// 2) الدعم الفني يتحقق من هويته ويرد برمز تفويض موقَّع.
/// 3) يلصق رمز التفويض هنا ويختار كلمة سر جديدة.
///
/// يُغلق بالرمز الجديد للاسترداد (String) عند النجاح، وإلا null.
class LostRecoveryCodeDialog extends StatefulWidget {
  const LostRecoveryCodeDialog({super.key});

  @override
  State<LostRecoveryCodeDialog> createState() => _LostRecoveryCodeDialogState();
}

class _LostRecoveryCodeDialogState extends State<LostRecoveryCodeDialog> {
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _request;
  bool _loadingRequest = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _loadRequest({bool forceNew = false}) async {
    setState(() {
      _loadingRequest = true;
      _error = null;
    });
    try {
      final request =
          await context.read<AuthCubit>().createResetRequest(forceNew: forceNew);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loadingRequest = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _request = null;
        _loadingRequest = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _submit() async {
    final passwordError = validatePassword(_password.text);
    if (_token.text.trim().isEmpty) {
      setState(() => _error = 'ألصق رمز التفويض الذي أرسله لك الدعم الفني');
      return;
    }
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'كلمتا السر غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final newCode = await context.read<AuthCubit>().resetWithAuthorization(
            authorizationCode: _token.text,
            newPassword: _password.text,
          );
      if (mounted) Navigator.of(context).pop(newCode);
    } catch (e) {
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
    final request = _request;
    return AppDialog(
      title: 'فقدت رمز الاسترداد',
      icon: Icons.support_agent_rounded,
      iconColor: AppColors.warning,
      width: 520,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: (_busy || request == null) ? null : _submit,
          child: const Text('تعيين كلمة سر جديدة'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الخطوة 1: أرسل رمز الطلب التالي إلى الدعم الفني (واتساب مثلًا) '
            'مع ما يثبت أنك صاحب الصالة. سيتحققون منك ثم يرسلون لك رمز تفويض. '
            'بياناتك كلها تبقى كما هي.',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Container(
            padding: const EdgeInsets.all(Dimensions.spaceM),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(Dimensions.radiusM),
              border: Border.all(color: AppColors.border),
            ),
            child: _loadingRequest
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        request ?? '—',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.timer(AppColors.secondary, 15),
                      ),
                      if (request != null) ...[
                        const SizedBox(height: Dimensions.spaceS),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: Dimensions.spaceS,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: request));
                                showAppSnack(context, 'تم نسخ رمز الطلب');
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text('نسخ رمز الطلب'),
                            ),
                            TextButton(
                              onPressed:
                                  _busy ? null : () => _loadRequest(forceNew: true),
                              child: const Text('طلب جديد'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: Dimensions.spaceS),
          Text(
            'يمكنك إغلاق هذه النافذة وفتحها لاحقًا: يبقى الطلب نفسه صالحًا ما لم '
            'تضغط "طلب جديد" (وعندها يبطل أي رمز تفويض لطلب سابق).',
            style: AppTextStyles.bodySmall(AppColors.textMuted),
          ),
          const SizedBox(height: Dimensions.spaceM),
          Text(
            'الخطوة 2: ألصق رمز التفويض الذي وصلك واختر كلمة سر جديدة.',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          const SizedBox(height: Dimensions.spaceS),
          TextField(
            controller: _token,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'رمز التفويض (A1....)',
              prefixIcon: Icon(Icons.verified_user_rounded),
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'كلمة السر الجديدة',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            obscureText: true,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'تأكيد كلمة السر الجديدة',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceS),
            Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],
        ],
      ),
    );
  }
}
