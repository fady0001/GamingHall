import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/text_styles.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  /// لون الأيقونة (الافتراضي بنفسجي فاتح).
  final Color? color;

  const SectionTitle(
      {super.key, required this.title, this.icon, this.trailing, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: color ?? AppColors.primaryLight),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(title, style: AppTextStyles.heading3())),
        if (trailing != null) trailing!,
      ],
    );
  }
}
