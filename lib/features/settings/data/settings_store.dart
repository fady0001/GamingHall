import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/domain/entities/billing_policy.dart';
import '../../../core/domain/value_objects/money.dart';
import '../domain/entities/app_settings.dart';

/// قراءة/كتابة جدول settings (مفتاح/قيمة). يُستخدم داخل المعاملات أيضًا لضمان
/// أن حساب الفاتورة يقرأ نفس الإعدادات التي رآها المستخدم.
class SettingsStore {
  SettingsStore._();

  static const String kLoungeName = 'lounge_name';
  static const String kLoungePhone = 'lounge_phone';
  static const String kInvoiceFooter = 'invoice_footer';
  static const String kMinimumInvoice = 'minimum_invoice';
  static const String kRoundingStep = 'rounding_step';
  static const String kReminderInterval = 'reminder_interval_minutes';
  static const String kAutoPrint = 'auto_print';
  static const String kPrinterName = 'printer_name';

  static Future<Map<String, String>> readAll(DatabaseExecutor ex) async {
    final rows = await ex.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  static Future<String?> readValue(DatabaseExecutor ex, String key) async {
    final rows = await ex.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  static Future<void> writeValue(
      DatabaseExecutor ex, String key, String value) async {
    await ex.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteValue(DatabaseExecutor ex, String key) async {
    await ex.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  /// القيم المسموحة لفاصل التذكير (بالدقائق): 0 = إيقاف.
  static int _validReminder(int v, int fallback) =>
      const [0, 15, 30, 60].contains(v) ? v : fallback;

  static AppSettings fromMap(Map<String, String> m) {
    const d = AppSettings();
    int intOf(String key, int fallback) => int.tryParse(m[key] ?? '') ?? fallback;
    return AppSettings(
      loungeName: (m[kLoungeName]?.trim().isNotEmpty ?? false)
          ? m[kLoungeName]!.trim()
          : d.loungeName,
      loungePhone: m[kLoungePhone] ?? d.loungePhone,
      invoiceFooter: m[kInvoiceFooter] ?? d.invoiceFooter,
      minimumInvoice: Money(intOf(kMinimumInvoice, d.minimumInvoice.amount)),
      roundingStep: intOf(kRoundingStep, d.roundingStep).clamp(1, 100000),
      reminderIntervalMinutes: _validReminder(
          intOf(kReminderInterval, d.reminderIntervalMinutes), d.reminderIntervalMinutes),
      autoPrint: (m[kAutoPrint] ?? '0') == '1',
      printerName: m[kPrinterName] ?? d.printerName,
    );
  }

  static Future<AppSettings> readSettings(DatabaseExecutor ex) async =>
      fromMap(await readAll(ex));

  static Future<BillingPolicy> readBillingPolicy(DatabaseExecutor ex) async =>
      (await readSettings(ex)).billingPolicy;

  static Future<void> writeSettings(
      DatabaseExecutor ex, AppSettings s) async {
    await writeValue(ex, kLoungeName, s.loungeName.trim());
    await writeValue(ex, kLoungePhone, s.loungePhone.trim());
    await writeValue(ex, kInvoiceFooter, s.invoiceFooter.trim());
    await writeValue(ex, kMinimumInvoice, s.minimumInvoice.amount.toString());
    await writeValue(ex, kRoundingStep, s.roundingStep.toString());
    await writeValue(ex, kReminderInterval, s.reminderIntervalMinutes.toString());
    await writeValue(ex, kAutoPrint, s.autoPrint ? '1' : '0');
    await writeValue(ex, kPrinterName, s.printerName.trim());
  }
}
