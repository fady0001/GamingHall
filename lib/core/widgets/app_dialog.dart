import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_styles.dart';

/// هيكل حوار موحّد: عنوان بأيقونة، محتوى قابل للتمرير، وأزرار.
class AppDialog extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Widget child;
  final List<Widget> actions;
  final double width;

  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.icon,
    this.iconColor,
    this.width = 460,
  });

  @override
  Widget build(BuildContext context) {
    final iconTint = iconColor ?? AppColors.primaryLight;
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 600;
    final pad = narrow ? Dimensions.spaceM : Dimensions.spaceL;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? Dimensions.spaceS : Dimensions.spaceL,
        vertical: narrow ? Dimensions.spaceS : Dimensions.spaceL,
      ),
      child: ConstrainedBox(
        // الارتفاع يتبع الشاشة (لا رقم ثابت) والعرض لا يتجاوز الشاشة أبدًا.
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: (size.height - 2 * Dimensions.spaceL).clamp(240.0, 760.0),
        ),
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconTint.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(Dimensions.radiusM),
                      ),
                      child: Icon(icon, color: iconTint, size: 22),
                    ),
                    const SizedBox(width: Dimensions.spaceS),
                  ],
                  Expanded(child: Text(title, style: AppTextStyles.heading2())),
                ],
              ),
              const SizedBox(height: Dimensions.spaceM),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: Dimensions.spaceL),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Dimensions.spaceS,
                runSpacing: Dimensions.spaceXS,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حوار تأكيد. يعيد true فقط عند التأكيد الصريح.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool danger = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: title,
      icon: icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
      iconColor: danger ? AppColors.danger : AppColors.primaryLight,
      width: 420,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message, style: AppTextStyles.bodyLarge(AppColors.textSecondary)),
    ),
  );
  return result ?? false;
}
