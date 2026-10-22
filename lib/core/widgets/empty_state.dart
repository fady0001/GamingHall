import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_styles.dart';

/// حالة "لا يوجد شيء بعد" مع شرح ما يجب فعله (تجنّب الشاشات الفارغة الصامتة).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.spaceL),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, size: 34, color: AppColors.textSecondary),
              ),
              const SizedBox(height: Dimensions.spaceM),
              Text(title,
                  style: AppTextStyles.heading3(), textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: Dimensions.spaceXS),
                Text(message!,
                    style: AppTextStyles.bodyMedium(AppColors.textSecondary),
                    textAlign: TextAlign.center),
              ],
              if (action != null) ...[
                const SizedBox(height: Dimensions.spaceM),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
