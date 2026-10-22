import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_info.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../cubit/auth_cubit.dart';
import '../widgets/manager_login_dialog.dart';

/// شاشة البداية: "موظف" (دخول فوري بدون حساب) أو "مدير" (اسم مستخدم وكلمة سر).
class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final loungeName = context.select((SettingsCubit c) => c.state.settings.loungeName);
    final notice = context.select((AuthCubit c) => c.state.autoLoggedOutNotice);

    if (notice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showAppSnack(context, 'عدنا إلى شاشة الدخول لأن وضع المدير بقي بدون استخدام.');
        context.read<AuthCubit>().acknowledgeNotice();
      });
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.15,
            colors: [AppColors.isDark ? const Color(0xFF1B1646) : const Color(0xFFE3E6FB), AppColors.background],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dimensions.spaceL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.45),
                          blurRadius: 36,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.sports_esports_rounded,
                        size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: Dimensions.spaceL),
                  Text(loungeName, style: AppTextStyles.display()),
                  const SizedBox(height: Dimensions.spaceXS),
                  Text(AppInfo.tagline,
                      style: AppTextStyles.bodyLarge(AppColors.textSecondary)),
                  const SizedBox(height: Dimensions.spaceXL),
                  Text('كيف تريد الدخول؟', style: AppTextStyles.heading2()),
                  const SizedBox(height: Dimensions.spaceL),
                  Row(
                    children: [
                      Expanded(
                        child: _RoleCard(
                          icon: Icons.badge_rounded,
                          title: 'موظف',
                          subtitle: 'الفواتير والحجوزات وتشغيل الأجهزة',
                          color: AppColors.secondary,
                          onTap: () => context.read<AuthCubit>().continueAsEmployee(),
                        ),
                      ),
                      const SizedBox(width: Dimensions.spaceM),
                      Expanded(
                        child: _RoleCard(
                          icon: Icons.admin_panel_settings_rounded,
                          title: 'مدير',
                          subtitle: 'الأسعار والتقارير والإعدادات',
                          color: AppColors.primaryLight,
                          onTap: () => showManagerLoginDialog(context),
                        ),
                      ),
                    ],
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

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      accentColor: color,
      glow: true,
      padding: const EdgeInsets.symmetric(
        horizontal: Dimensions.spaceL,
        vertical: Dimensions.spaceXL,
      ),
      child: Column(
        children: [
          Icon(icon, size: 52, color: color),
          const SizedBox(height: Dimensions.spaceM),
          Text(title, style: AppTextStyles.heading1()),
          const SizedBox(height: Dimensions.spaceXS),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
        ],
      ),
    );
  }
}
