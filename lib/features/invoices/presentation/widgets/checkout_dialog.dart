import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/theme/text_styles.dart';

/// حوار "محاسبة وإغلاق": يعرض الإجمالي ويسمح بتعديل اسم الزبون الذي كُتب
/// عند إنشاء الفاتورة قبل إغلاقها نهائيًا.
///
/// يعيد الاسم النهائي (بعد القص) عند التأكيد، أو null عند الإلغاء.
Future<String?> showCheckoutDialog(
  BuildContext context, {
  required String customerName,
  required String message,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CheckoutDialog(customerName: customerName, message: message),
  );
}

class _CheckoutDialog extends StatefulWidget {
  final String customerName;
  final String message;
  const _CheckoutDialog({required this.customerName, required this.message});

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  static const int _maxLength = 60;

  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.customerName);
    _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الزبون مطلوب');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'محاسبة الفاتورة؟',
      icon: Icons.point_of_sale_rounded,
      width: 440,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('محاسبة وإغلاق'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.message,
            style: AppTextStyles.bodyLarge(AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: _maxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'اسم الزبون (يمكنك تعديله قبل الإغلاق)',
              prefixIcon: const Icon(Icons.person_rounded),
              errorText: _error,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}
