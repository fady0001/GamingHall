import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../domain/repositories/auth_repository.dart';
import '../cubit/auth_cubit.dart';
import 'recovery_code_dialog.dart';

/// تسجيل دخول المدير. يُغلق بـ true عند النجاح.
Future<bool> showManagerLoginDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ManagerLoginDialog(),
  );
  return ok ?? false;
}

class _ManagerLoginDialog extends StatefulWidget {
  const _ManagerLoginDialog();

  @override
  State<_ManagerLoginDialog> createState() => _ManagerLoginDialogState();
}

class _ManagerLoginDialogState extends State<_ManagerLoginDialog> {
  // اسم المستخدم لا يُعبّأ تلقائيًا: المدير يكتب الاسم وكلمة السر بنفسه.
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة السر');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await context.read<AuthCubit>().loginAsManager(
            username: _username.text,
            password: _password.text,
          );
      if (!mounted) return;
      if (outcome.success) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _busy = false;
        _password.clear();
        if (outcome.isLocked) {
          final d = outcome.lockedFor!;
          final wait = d.inMinutes >= 1
              ? '${d.inMinutes} دقيقة'
              : '${d.inSeconds.clamp(1, 59)} ثانية';
          _error = 'محاولات خاطئة كثيرة. الحساب مقفل مؤقتًا، حاول بعد $wait.';
        } else {
          _error = 'اسم المستخدم أو كلمة السر غير صحيحة. '
              'المحاولات المتبقية قبل القفل المؤقت: ${outcome.attemptsLeft}';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _forgot() async {
    final auth = context.read<AuthCubit>();
    final newCode = await showDialog<String>(
      context: context,
      builder: (_) => BlocProvider.value(value: auth, child: const _RecoveryDialog()),
    );
    if (newCode != null && mounted) {
      await showRecoveryCodeDialog(context, newCode);
      if (mounted) {
        setState(() => _error = null);
        ScaffoldMessenger.maybeOf(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'دخول المدير',
      icon: Icons.admin_panel_settings_rounded,
      width: 440,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('دخول'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _username,
            enabled: !_busy,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: _obscure,
            textDirection: TextDirection.ltr,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'كلمة السر',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceS),
            Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],
          const SizedBox(height: Dimensions.spaceXS),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _busy ? null : _forgot,
              child: const Text('نسيت كلمة السر؟'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog();

  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passwordError = validatePassword(_password.text);
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'أدخل رمز الاسترداد');
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
      final newCode = await context.read<AuthCubit>().resetPassword(
            recoveryCode: _code.text,
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
    return AppDialog(
      title: 'استرداد كلمة السر',
      icon: Icons.key_rounded,
      iconColor: AppColors.warning,
      width: 460,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('تعيين كلمة سر جديدة'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('أدخل رمز الاسترداد الذي حفظته عند إنشاء الحساب.',
              style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _code,
            enabled: !_busy,
            autofocus: true,
            textDirection: TextDirection.ltr,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'رمز الاسترداد (XXXX-XXXX-XXXX-XXXX)',
              prefixIcon: Icon(Icons.vpn_key_rounded),
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
