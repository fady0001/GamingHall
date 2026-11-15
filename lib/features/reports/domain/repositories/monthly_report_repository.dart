import '../entities/monthly_report.dart';

abstract class MonthlyReportRepository {
  /// يبني تقرير شهر ([month] من 1 إلى 12).
  Future<MonthlyReport> build(int year, int month);

  /// أول شهر فيه نشاط (يوم عمل أو مصروف)، أو null إن لم يوجد شيء بعد.
  Future<DateTime?> earliestMonth();
}
