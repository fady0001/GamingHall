import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../settings/domain/entities/app_settings.dart';
import '../domain/entities/monthly_report.dart';
import 'monthly_report_pdf_builder.dart';

/// حفظ التقرير الشهري PDF في `Documents\GamingHall\Reports` وفتحه.
class MonthlyReportExporter {
  MonthlyReportExporter._();

  static Future<Directory> reportsDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'GamingHall', 'Reports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// اسم الملف: `monthly-report-2026-11.pdf`.
  static String fileName(int year, int month) =>
      'monthly-report-$year-${month.toString().padLeft(2, '0')}.pdf';

  /// يبني الـPDF ويحفظه ويعيد مساره. إعادة إنشاء نفس الشهر تستبدل الملف؛ وإن
  /// كان مفتوحًا في برنامج آخر (ويندوز يقفله) نحفظ نسخة باسم جديد بدل الفشل.
  static Future<String> save(MonthlyReport report, AppSettings settings) async {
    final bytes = await MonthlyReportPdfBuilder.build(report, settings);
    final dir = await reportsDirectory();
    final name = fileName(report.year, report.month);
    final file = File(p.join(dir.path, name));
    try {
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on FileSystemException {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final alt = File(p.join(
          dir.path, '${p.basenameWithoutExtension(name)}-$stamp.pdf'));
      await alt.writeAsBytes(bytes, flush: true);
      return alt.path;
    }
  }

  /// يفتح الملف بالبرنامج الافتراضي (فشل الفتح لا يُعدّ خطأ في الحفظ).
  static Future<void> open(String filePath) async {
    try {
      await Process.run('explorer', [filePath]);
    } catch (_) {}
  }
}
