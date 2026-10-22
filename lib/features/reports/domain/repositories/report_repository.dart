import '../entities/report.dart';

abstract class ReportRepository {
  Future<Report> build(DateRange range);
}
