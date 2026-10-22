import '../entities/work_day.dart';

abstract class WorkDayRepository {
  /// يوم العمل المفتوح حاليًا (يُنشأ تلقائيًا إن لم يوجد).
  Future<WorkDay> currentDay();

  Stream<WorkDay> watchCurrentDay();

  /// يغلق اليوم الحالي ويفتح يومًا جديدًا. يرمي [OpenInvoicesException]
  /// إن بقيت فواتير مفتوحة (يجب محاسبتها أولًا، لا نحاسب أحدًا تلقائيًا).
  Future<WorkDay> startNewDay();

  /// كل الأيام مع إحصاءاتها، الأحدث أولًا.
  Stream<List<WorkDaySummary>> watchSummaries({int limit = 400});
}

class OpenInvoicesException implements Exception {
  final List<String> customerNames;
  const OpenInvoicesException(this.customerNames);

  @override
  String toString() {
    final shown = customerNames.take(5).join('، ');
    final more = customerNames.length > 5 ? ' و${customerNames.length - 5} آخرين' : '';
    return 'لا يمكن بدء يوم عمل جديد قبل محاسبة كل الفواتير المفتوحة: $shown$more.';
  }
}
