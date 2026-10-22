import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../invoices/domain/entities/invoice.dart';
import '../../settings/domain/entities/app_settings.dart';
import 'invoice_pdf_builder.dart';

/// الطباعة وحفظ الفاتورة كملف. الطباعة المباشرة تستخدم الطابعة المضبوطة في
/// الإعدادات، وإن لم تُضبط فطابعة ويندوز الافتراضية.
class InvoicePrinter {
  InvoicePrinter._();

  static const PdfPageFormat format = PdfPageFormat.roll80;

  /// يطبع مباشرة دون أي نافذة. يعيد null عند النجاح أو رسالة خطأ للعرض.
  static Future<String?> printDirect(Invoice invoice, AppSettings settings) async {
    try {
      final printers = await Printing.listPrinters();
      if (printers.isEmpty) {
        return 'لا توجد أي طابعة مثبّتة على هذا الجهاز.';
      }

      Printer? chosen;
      final wanted = settings.printerName.trim();
      if (wanted.isNotEmpty) {
        for (final printer in printers) {
          if (printer.name == wanted) chosen = printer;
        }
        if (chosen == null) {
          return 'الطابعة المضبوطة "$wanted" غير موجودة أو غير متصلة. '
              'غيّرها من الإعدادات أو وصّلها.';
        }
      } else {
        for (final printer in printers) {
          if (printer.isDefault) chosen = printer;
        }
        if (chosen == null) {
          return 'لا توجد طابعة افتراضية. اختر طابعة الفواتير من الإعدادات، '
              'أو اضبطها كافتراضية في ويندوز.';
        }
      }

      final ok = await Printing.directPrintPdf(
        printer: chosen,
        onLayout: (f) => InvoicePdfBuilder.build(invoice, settings, f),
        format: format,
        name: 'invoice-${invoice.id}',
      );
      return ok ? null : 'تعذّر إرسال الفاتورة إلى الطابعة.';
    } catch (e) {
      return 'تعذّرت الطباعة: $e';
    }
  }

  static Future<Directory> invoicesDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'GamingHall', 'Invoices'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// يحفظ الفاتورة PDF في مجلد المستندات ويعيد مسار الملف.
  static Future<String> savePdf(Invoice invoice, AppSettings settings) async {
    final bytes = await InvoicePdfBuilder.build(invoice, settings, format);
    final dir = await invoicesDirectory();
    final file = File(p.join(dir.path, 'invoice-${invoice.id}.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// يفتح مجلد الملف في مستكشف ويندوز مع تحديد الملف.
  static Future<void> revealInExplorer(String filePath) async {
    try {
      await Process.run('explorer', ['/select,', filePath]);
    } catch (_) {}
  }

  static Future<List<String>> printerNames() async {
    try {
      final printers = await Printing.listPrinters();
      return printers.map((p) => p.name).toList();
    } catch (_) {
      return const [];
    }
  }
}
