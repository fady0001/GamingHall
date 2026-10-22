import '../../../../core/utils/time_format.dart';

/// "يوم عمل" واحد في الصالة. يبقى مفتوحًا حتى يضغط الموظف "يوم عمل جديد"،
/// فيُؤرشف ويُفتح يوم جديد. لا يُحذف أي شيء أبدًا.
class WorkDay {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;

  const WorkDay({required this.id, required this.startedAt, this.endedAt});

  bool get isOpen => endedAt == null;

  String get dateKey => formatDate(startedAt);

  String get dayName => arabicDayName(startedAt);

  /// مثال: `2026-10-01 - الخميس`
  String get label => '$dateKey - $dayName';
}

/// يوم عمل مع إحصاءاته (لقائمة السجل).
class WorkDaySummary {
  final WorkDay day;
  final int invoiceCount;
  final int totalRevenue;

  const WorkDaySummary({
    required this.day,
    required this.invoiceCount,
    required this.totalRevenue,
  });
}
