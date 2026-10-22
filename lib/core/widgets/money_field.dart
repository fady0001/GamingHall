import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_info.dart';
import '../utils/number_format.dart';

/// حقل مبلغ بالليرة: أرقام فقط، فاصلة آلاف تلقائية، واتجاه لاتيني.
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩,]')),
        ThousandsSeparatorFormatter(),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        suffixText: AppInfo.currencyLabel,
        prefixIcon: const Icon(Icons.payments_outlined),
      ),
    );
  }
}
