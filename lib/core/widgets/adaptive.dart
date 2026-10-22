import 'package:flutter/material.dart';

/// نقاط التوقف للتصميم المتجاوب.
class Breakpoints {
  Breakpoints._();

  /// أقل من هذا العرض: الشريط الجانبي يصير قائمة منسدلة (Drawer).
  static const double compact = 900;

  /// أقل من هذا: تخطيط الهاتف (عمود واحد، أزرار بعرض كامل).
  static const double phone = 600;
}

extension AdaptiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => screenWidth < Breakpoints.compact;
  bool get isPhone => screenWidth < Breakpoints.phone;
}

/// عنصران جنبًا إلى جنب، وإن ضاق المكان (أقل من [breakAt]) صارا فوق بعض.
class AdaptiveRow extends StatelessWidget {
  final Widget first;
  final Widget second;
  final double gap;
  final double breakAt;

  const AdaptiveRow({
    super.key,
    required this.first,
    required this.second,
    this.gap = 12,
    this.breakAt = 420,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakAt) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, SizedBox(height: gap), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: gap),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// بديل عن Row أبناؤه Expanded + فواصل SizedBox: على عرض أقل من [breakAt]
/// يصير عمودًا (الأبناء تحت بعض والفواصل رأسية) بدل أن تضيق البطاقات.
class AdaptiveExpandedRow extends StatelessWidget {
  final List<Widget> children;
  final double breakAt;
  final CrossAxisAlignment crossAxisAlignment;

  const AdaptiveExpandedRow({
    super.key,
    required this.children,
    this.breakAt = 640,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= breakAt) {
          return Row(crossAxisAlignment: crossAxisAlignment, children: children);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final w in children)
              if (w is Expanded)
                w.child
              else if (w is SizedBox && w.width != null && w.child == null)
                SizedBox(height: w.width)
              else
                w,
          ],
        );
      },
    );
  }
}
