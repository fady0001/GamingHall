import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/number_format.dart';

/// حقل عدد صحيح (أرقام فقط، اتجاه لاتيني).
class IntField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const IntField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.errorText,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]'))],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

/// يقرأ عددًا صحيحًا من نص المستخدم (يقبل الأرقام العربية). null إن كان فارغًا.
int? parseIntField(String text) {
  final digits = toLatinDigits(text).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty || digits.length > 9) return null;
  return int.tryParse(digits);
}
