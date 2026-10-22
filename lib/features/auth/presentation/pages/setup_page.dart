import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_info.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../cubit/auth_cubit.dart';
import '../../domain/repositories/auth_repository.dart';
import '../widgets/recovery_code_dialog.dart';

/// الإعداد الأول (مرة واحدة): اسم الصالة وحساب المدير. لا توجد كلمة سر
/// افتراضية في أي مكان؛ صاحب الصالة هو من ينشئها.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _loungeName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _loungeName.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lounge = _loungeName.text.trim();
    final username = _username.text.trim();
    final password = _password.text;

    String? error;
    if (lounge.isEmpty) {
      error = 'اكتب اسم الصالة (يظهر على الفاتورة)';
    } else if (username.length < 3) {
      error = 'اسم المستخدم يجب ألا يقل عن 3 أحرف';
    } else if (validatePassword(password) != null) {
      error = validatePassword(password);
    } else if (password != _confirm.text) {
      error = 'كلمتا السر غير متطابقتين';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = context.read<AuthCubit>();
    final settings = context.read<SettingsCubit>();
    try {
      await settings.save(settings.state.settings.copyWith(loungeName: lounge));
      final code = await auth.setUpManager(username: username, password: password);
      if (!mounted) return;
      await showRecoveryCodeDialog(context, code);
      auth.finishSetup();
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
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.2,
            colors: [AppColors.isDark ? const Color(0xFF1B1646) : const Color(0xFFE3E6FB), AppColors.background],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dimensions.spaceL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.sports_esports_rounded,
                          size: 40, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceM),
                  Text('مرحبًا بك في ${AppInfo.englishName}',
                      textAlign: TextAlign.center, style: AppTextStyles.heading1()),
                  const SizedBox(height: Dimensions.spaceXS),
                  Text(
                    'خطوة واحدة قبل البدء: أنشئ حساب المدير. بدونه لا يمكن لأحد '
                    'تعديل الأسعار أو رؤية التقارير.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium(AppColors.textSecondary),
                  ),
                  const SizedBox(height: Dimensions.spaceL),
                  Container(
                    padding: const EdgeInsets.all(Dimensions.spaceL),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(Dimensions.radiusL),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _loungeName,
                          autofocus: true,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'اسم الصالة (يظهر على الفاتورة)',
                            prefixIcon: Icon(Icons.storefront_rounded),
                          ),
                        ),
                        const SizedBox(height: Dimensions.spaceM),
                        TextField(
                          controller: _username,
                          enabled: !_busy,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'اسم مستخدم المدير',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                        ),
                        const SizedBox(height: Dimensions.spaceM),
                        TextField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'كلمة السر (6 أحرف على الأقل)',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(height: Dimensions.spaceM),
                        TextField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'تأكيد كلمة السر',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Dimensions.spaceS),
                          Text(_error!,
                              style: AppTextStyles.bodyMedium(AppColors.danger)),
                        ],
                        const SizedBox(height: Dimensions.spaceL),
                        SizedBox(
                          height: Dimensions.buttonHeightLarge,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Text('إنشاء الحساب والبدء'),
                          ),
                        ),
                      ],
                    ),
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
