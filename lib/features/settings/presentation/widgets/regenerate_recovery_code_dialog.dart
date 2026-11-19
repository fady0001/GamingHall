import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

/// يطلب كلمة السر الحالية ثم يُنشئ رمز استرداد جديدًا يُبطل القديم فورًا.
/// يعيد الرمز الجديد (ليعرضه المستدعي مرة واحدة)، أو null عند الإلغاء.
Future<String?> showRegenerateRecoveryCodeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _RegenerateRecoveryCodeDialog(),
  );
}

class _RegenerateRecoveryCodeDialog extends StatefulWidget {
  const _RegenerateRecoveryCodeDialog();

  @override
  State<_RegenerateRecoveryCodeDialog> createState() =>
      _RegenerateRecoveryCodeDialogState();
}

class _RegenerateRecoveryCodeDialogState
    extends State<_RegenerateRecoveryCodeDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'أدخل كلمة السر الحالية');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await context
          .read<AuthCubit>()
          .regenerateRecoveryCode(currentPassword: _password.text);
      if (mounted) Navigator.of(context).pop(code);
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
    return AppDialog(
      title: 'إنشاء رمز استرداد جديد',
      icon: Icons.key_rounded,
      iconColor: AppColors.warning,
      width: 440,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('إنشاء رمز جديد'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'سيُنشأ رمز استرداد جديد ويبطل الرمز القديم فورًا (حتى لو كان محفوظًا '
            'عندك). استخدم هذا إن ضاع الرمز أو شككت أن أحدًا اطّلع عليه. '
            'الرمز الجديد يظهر مرة واحدة فقط.',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _password,
            enabled: !_busy,
            autofocus: true,
            obscureText: true,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'كلمة السر الحالية',
              prefixIcon: Icon(Icons.lock_rounded),
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
