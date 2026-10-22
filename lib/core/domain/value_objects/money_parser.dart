import 'money.dart';
import '../../utils/number_format.dart';

/// يحوّل نصًا يكتبه المستخدم إلى مبلغ. يقبل الأرقام العربية والفواصل
/// (`5,000` أو `٥٠٠٠`). يعيد null إن كان النص فارغًا أو غير صالح.
Money? parseMoney(String input) {
  final digits = toLatinDigits(input).replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty || digits.length > 12) return null;
  final value = int.tryParse(digits);
  if (value == null) return null;
  return Money(value);
}
