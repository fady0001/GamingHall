import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';

Future<bool> showChangePasswordDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );
  return ok ?? false;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final passwordError = validatePassword(_new.text);
    if (_current.text.isEmpty) {
      setState(() => _error = 'أدخل كلمة السر الحالية');
      return;
    }
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'كلمتا السر الجديدتان غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthCubit>().changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (mounted) Navigator.of(context).pop(true);
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
    Widget field(TextEditingController c, String label, {bool autofocus = false, VoidCallback? submit}) {
      return TextField(
        controller: c,
        enabled: !_busy,
        autofocus: autofocus,
        obscureText: true,
        textDirection: TextDirection.ltr,
        onSubmitted: submit == null ? null : (_) => submit(),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_rounded),
        ),
      );
    }

    return AppDialog(
      title: 'تغيير كلمة سر المدير',
      icon: Icons.lock_reset_rounded,
      width: 440,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('تغيير'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(_current, 'كلمة السر الحالية', autofocus: true),
          const SizedBox(height: Dimensions.spaceM),
          field(_new, 'كلمة السر الجديدة'),
          const SizedBox(height: Dimensions.spaceM),
          field(_confirm, 'تأكيد كلمة السر الجديدة', submit: _submit),
          if (_error != null) ...[
            const SizedBox(height: Dimensions.spaceS),
            Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
          ],
        ],
      ),
    );
  }
}
