import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities/game_resource.dart';
import '../../domain/entities/resource_kind.dart';

/// صف جهاز/طاولة/لعبة في صفحة القسم: الاسم والأسعار ومفتاح "خارج الخدمة"
/// وأزرار التعديل والحذف.
///
/// التخطيط ثابت المواضع: منطقة الإجراءات (المفتاح + تعديل + حذف) بعرض ثابت
/// وفي نفس المكان في كل الصفوف مهما اختلف عدد الأسعار أو ظهرت شارة "خارج
/// الخدمة" (الشارة تحت الاسم فلا تزيح الأزرار). وعلى العرض الضيق ينقلب
/// الصف إلى عمودين: المعلومات فوق والإجراءات في شريط واحد تحتها.
class ResourceRow extends StatelessWidget {
  final GameResource resource;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const ResourceRow({
    super.key,
    required this.resource,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  /// أقل من هذا العرض (داخل البطاقة) يُستعمل التخطيط العمودي.
  static const double _wideBreakpoint = 760;

  /// عرض منطقة الإجراءات في التخطيط العريض: مفتاح 120 + زرّان 48 + فواصل.
  static const double _actionsWidth = 120 + 48 + 48 + 8 + 4;

  @override
  Widget build(BuildContext context) {
    final r = resource;
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: Dimensions.spaceM, vertical: Dimensions.spaceS),
      child: Opacity(
        opacity: r.outOfService ? 0.7 : 1,
        child: LayoutBuilder(
          builder: (context, c) {
            return c.maxWidth >= _wideBreakpoint
                ? _wide(context)
                : _narrow(context);
          },
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- عريض

  Widget _wide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 3, child: _nameBlock()),
        const SizedBox(width: Dimensions.spaceM),
        Expanded(flex: 5, child: _rates()),
        const SizedBox(width: Dimensions.spaceM),
        SizedBox(
          width: _actionsWidth,
          child: Row(
            children: [
              SizedBox(width: 120, child: _serviceSwitch(vertical: true)),
              const SizedBox(width: 4),
              _editButton(),
              const SizedBox(width: 4),
              _deleteButton(),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ ضيق

  Widget _narrow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nameBlock(),
        const SizedBox(height: Dimensions.spaceS),
        _rates(),
        const SizedBox(height: Dimensions.spaceXS),
        const Divider(height: 1),
        const SizedBox(height: Dimensions.spaceXXS),
        Row(
          children: [
            Expanded(child: _serviceSwitch(vertical: false)),
            _editButton(),
            const SizedBox(width: 4),
            _deleteButton(),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------- مكوّنات

  Widget _nameBlock() {
    final r = resource;
    // للطاولة نكتب نوعها (بلياردو...) تحت الاسم؛ لغيرها لا حاجة لتكرار اسم القسم.
    final subtitle = r.kind == ResourceKind.table ? r.typeLabel : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.heading3()),
        if (subtitle != null)
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall()),
        if (r.outOfService) ...[
          const SizedBox(height: 6),
          const StatusBadge(
            label: 'خارج الخدمة',
            color: AppColors.statusOutOfService,
            icon: Icons.block_rounded,
          ),
        ],
      ],
    );
  }

  Widget _rates() {
    final r = resource;
    final count = r.kind.hasPlayerPricing ? r.maxPlayers : 1;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              r.kind.hasPlayerPricing
                  ? '${i + 1} ${i == 0 ? 'لاعب' : 'لاعبين'}: ${formatMoney(r.hourlyRates[i])}'
                  : 'سعر الساعة: ${formatMoney(r.hourlyRates[i])}',
              style: AppTextStyles.bodySmall(AppColors.textPrimary),
            ),
          ),
      ],
    );
  }

  /// مفتاح "خارج الخدمة". عموديًا (نص فوق المفتاح) في التخطيط العريض، وأفقيًا
  /// (نص ثم المفتاح) في الضيق.
  Widget _serviceSwitch({required bool vertical}) {
    final label = Text('خارج الخدمة', style: AppTextStyles.bodySmall());
    final sw = Switch(value: resource.outOfService, onChanged: onToggle);
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [label, sw],
      );
    }
    return Row(
      children: [
        sw,
        const SizedBox(width: Dimensions.spaceXS),
        Flexible(child: label),
      ],
    );
  }

  Widget _editButton() => IconButton(
        tooltip: 'تعديل',
        onPressed: onEdit,
        icon: const Icon(Icons.edit_rounded),
      );

  Widget _deleteButton() => IconButton(
        tooltip: 'حذف',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      );
}
