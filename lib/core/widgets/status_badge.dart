import 'package:flutter/material.dart';

import '../theme/text_styles.dart';

/// شارة صغيرة (أيقونة + نص) بلون الحالة. لا نعتمد على اللون وحده لتمييز الحالة.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.9 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? Colors.black : color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.label(filled ? Colors.black : color)
                .copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
