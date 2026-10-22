import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_styles.dart';
import 'adaptive.dart';

/// ترويسة موحّدة أعلى كل صفحة داخل الإطار الرئيسي.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < Breakpoints.phone;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.heading1()),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
        ],
      ],
    );
    final pad = narrow ? Dimensions.spaceM : Dimensions.spaceL;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, Dimensions.spaceM),
      child: narrow
          // شاشة ضيقة: العنوان فوق والأزرار تحته وتلتف عند الحاجة.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: Dimensions.spaceS)],
                    Expanded(child: titleBlock),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: Dimensions.spaceS),
                  Wrap(spacing: Dimensions.spaceS, runSpacing: Dimensions.spaceS, children: actions),
                ],
              ],
            )
          : Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: Dimensions.spaceS)],
                Expanded(child: titleBlock),
                for (final a in actions) ...[
                  const SizedBox(width: Dimensions.spaceS),
                  a,
                ],
              ],
            ),
    );
  }
}
