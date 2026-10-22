import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_hall/core/domain/value_objects/money.dart';
import 'package:gaming_hall/core/domain/value_objects/money_parser.dart';
import 'package:gaming_hall/core/utils/arabic_search.dart';
import 'package:gaming_hall/core/utils/number_format.dart';
import 'package:gaming_hall/core/utils/time_format.dart';

void main() {
  test('فاصلة الآلاف', () {
    expect(groupThousands(0), '0');
    expect(groupThousands(999), '999');
    expect(groupThousands(1000), '1,000');
    expect(groupThousands(1234567), '1,234,567');
    expect(formatMoneyWithUnit(const Money(15000)), '15,000 ل.س');
  });

  test('قراءة المبلغ من نص (أرقام عربية وفواصل)', () {
    expect(parseMoney('5,000')?.amount, 5000);
    expect(parseMoney('٥٠٠٠')?.amount, 5000);
    expect(parseMoney('  12 000 ')?.amount, 12000);
    expect(parseMoney(''), isNull);
    expect(parseMoney('abc'), isNull);
  });

  test('تحويل الأرقام العربية', () {
    expect(toLatinDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    expect(toLatinDigits('۱۲۳'), '123');
  });

  test('بحث عربي يتجاهل الهمزات والتاء المربوطة والتشكيل', () {
    expect(normalizeForSearch('أحمد'), normalizeForSearch('احمد'));
    expect(normalizeForSearch('مَها'), normalizeForSearch('مها'));
    expect(normalizeForSearch('فاطمة'), normalizeForSearch('فاطمه'));
  });

  test('وصف المدد', () {
    expect(describeMinutes(45), '45 دقيقة');
    expect(describeMinutes(60), 'ساعة');
    expect(describeMinutes(80), 'ساعة و20 دقيقة');
    expect(describeMinutes(120), 'ساعتان');
    expect(describeMinutes(150), 'ساعتان و30 دقيقة');
  });

  test('تنسيق المدة', () {
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    expect(formatDuration(const Duration(minutes: 5, seconds: 9), compact: true), '05:09');
  });
}
