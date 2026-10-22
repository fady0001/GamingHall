import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/text_styles.dart';

/// رسالة عابرة أسفل الشاشة. [error] يلوّنها بالأحمر مع أيقونة.
void showAppSnack(
  BuildContext context,
  String message, {
  bool error = false,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  // الثيم يحدد عرضًا ثابتًا 520؛ نقيّده بعرض النافذة حتى لا يتجاوزها.
  final snackWidth = (MediaQuery.sizeOf(context).width - 32).clamp(240.0, 520.0);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: snackWidth,
        backgroundColor: error ? const Color(0xFF3A1522) : AppColors.surfaceHighest,
        duration: Duration(seconds: error ? 6 : 4),
        action: action,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: error ? AppColors.danger : AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: AppTextStyles.bodyMedium())),
          ],
        ),
      ),
    );
}
