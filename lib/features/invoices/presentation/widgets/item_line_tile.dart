import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/quantity_stepper.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../domain/entities/invoice.dart';
import '../cubit/invoices_cubit.dart';
import '../../../menu/domain/entities/menu_category.dart';

class ItemLineTile extends StatelessWidget {
  final ItemLine line;
  final bool editable;
  const ItemLineTile({super.key, required this.line, required this.editable});

  Future<void> _set(BuildContext context, int qty) async {
    try {
      await context.read<InvoicesCubit>().setItemQuantity(line.id, qty);
    } catch (e) {
      if (context.mounted) showAppSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(line.category.icon, color: AppColors.accent, size: 22);
    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line.name, style: AppTextStyles.bodyLarge()),
        Text('${formatMoneyWithUnit(line.unitPrice)} للواحد',
            style: AppTextStyles.bodySmall()),
      ],
    );
    final controls = editable
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              QuantityStepper(
                dense: true,
                value: line.quantity,
                min: 1,
                onChanged: (v) => _set(context, v),
              ),
              IconButton(
                tooltip: 'حذف من الفاتورة',
                onPressed: () => _set(context, 0),
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              ),
            ],
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('× ${line.quantity}',
                style: AppTextStyles.price(AppColors.textSecondary, 16)),
          );
    final total = Text(formatMoneyWithUnit(line.total),
        textAlign: TextAlign.end, style: AppTextStyles.price());

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimensions.spaceM,
        vertical: Dimensions.spaceS,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // مساحة ضيقة: السطر الأول (الاسم + المجموع) والثاني (الكمية + الحذف)
          // بدل صف واحد يتجاوز عرض البطاقة.
          if (c.maxWidth < 440) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: Dimensions.spaceS),
                    Expanded(child: nameBlock),
                    const SizedBox(width: Dimensions.spaceS),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: total,
                      ),
                    ),
                  ],
                ),
                if (editable) ...[
                  const SizedBox(height: 4),
                  Align(alignment: AlignmentDirectional.centerStart, child: controls),
                ] else
                  Align(alignment: AlignmentDirectional.centerStart, child: controls),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: Dimensions.spaceS),
              Expanded(child: nameBlock),
              controls,
              const SizedBox(width: Dimensions.spaceS),
              SizedBox(width: 110, child: total),
            ],
          );
        },
      ),
    );
  }
}
