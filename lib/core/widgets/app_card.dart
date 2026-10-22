import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/dimensions.dart';

/// بطاقة موحّدة للتطبيق: سطح داكن بحد خفيف، وتوهّج اختياري بلون الحالة، وتأثير
/// تحويم (Hover) عند قابليتها للنقر (مناسب لاستخدام الماوس على سطح المكتب).
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accentColor;
  final Color? color;
  final bool glow;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Dimensions.spaceM),
    this.onTap,
    this.accentColor,
    this.color,
    this.glow = false,
    this.radius = Dimensions.radiusL,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final tappable = widget.onTap != null;
    final borderColor = accent != null
        ? accent.withValues(alpha: _hovered ? 0.95 : 0.55)
        : (_hovered && tappable ? AppColors.primary : AppColors.border);

    final radius = BorderRadius.circular(widget.radius);

    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: widget.color ?? AppColors.surface,
          borderRadius: radius,
          border: Border.all(color: borderColor, width: accent != null ? 1.5 : 1),
          boxShadow: [
            if (widget.glow && accent != null)
              BoxShadow(
                color: accent.withValues(alpha: _hovered ? 0.28 : 0.16),
                blurRadius: 18,
                spreadRadius: 0,
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
