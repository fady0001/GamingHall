import 'package:flutter/services.dart';

import '../constants/app_info.dart';
import '../domain/value_objects/money.dart';

/// يحوّل الأرقام العربية-الهندية والفارسية إلى لاتينية.
String toLatinDigits(String input) {
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      buffer.writeCharCode(0x30 + (unit - 0x0660));
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      buffer.writeCharCode(0x30 + (unit - 0x06F0));
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// فاصلة الآلاف: 15000 -> 15,000
String groupThousands(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// المبلغ بدون وحدة: 15,000
String formatMoney(Money m) => groupThousands(m.amount);

/// المبلغ مع الوحدة: 15,000 ل.س
String formatMoneyWithUnit(Money m) =>
    '${groupThousands(m.amount)} ${AppInfo.currencyLabel}';

/// يضيف فاصلة الآلاف أثناء الكتابة في حقول الأسعار، ويقبل الأرقام فقط.
class ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = toLatinDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    if (digits.length > 12) digits = digits.substring(0, 12);
    final formatted = groupThousands(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
