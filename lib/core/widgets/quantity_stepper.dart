import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/text_styles.dart';

/// عدّاد صغير بزرّي + و−. يُستخدم للكميات وعدد اللاعبين.
class QuantityStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool dense;

  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 999,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = dense ? 32.0 : 40.0;
    Widget button(IconData icon, VoidCallback? onTap, String tooltip) {
      return SizedBox(
        width: size,
        height: size,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceHighest,
            disabledBackgroundColor: AppColors.surfaceHigh,
          ),
          onPressed: onTap,
          icon: Icon(icon, size: dense ? 18 : 22),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.add_rounded, value < max ? () => onChanged(value + 1) : null, 'زيادة'),
        SizedBox(
          width: dense ? 36 : 48,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTextStyles.price(AppColors.textPrimary, dense ? 16 : 20),
          ),
        ),
        button(Icons.remove_rounded, value > min ? () => onChanged(value - 1) : null, 'إنقاص'),
      ],
    );
  }
}
