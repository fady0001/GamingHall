import '../../../resources/domain/entities/resource_kind.dart';

/// فترة نصف مفتوحة [start, end).
class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);
}

enum RangePreset { today, week, month, custom }

extension RangePresetX on RangePreset {
  String get label {
    switch (this) {
      case RangePreset.today:
        return 'يوم العمل الحالي';
      case RangePreset.week:
        return 'هذا الأسبوع';
      case RangePreset.month:
        return 'هذا الشهر';
      case RangePreset.custom:
        return 'فترة مخصصة';
    }
  }
}

class ReportSummary {
  final int invoiceCount;
  final int revenue;
  final int playRevenue;
  final int itemsRevenue;

  const ReportSummary({
    required this.invoiceCount,
    required this.revenue,
    required this.playRevenue,
    required this.itemsRevenue,
  });

  int get averageInvoice => invoiceCount == 0 ? 0 : (revenue / invoiceCount).round();

  static const empty = ReportSummary(
      invoiceCount: 0, revenue: 0, playRevenue: 0, itemsRevenue: 0);
}

class DailySales {
  final String date; // yyyy-MM-dd
  final int invoiceCount;
  final int revenue;
  const DailySales(this.date, this.invoiceCount, this.revenue);
}

class ResourceStat {
  final int resourceId;
  final String name;
  final ResourceKind kind;

  /// نوع العرض: اسم نوع الطاولة (بلياردو...) أو اسم الفئة.
  final String typeLabel;
  final int revenue;
  final int minutes;
  final int sessions;
  const ResourceStat({
    required this.resourceId,
    required this.name,
    required this.kind,
    required this.typeLabel,
    required this.revenue,
    required this.minutes,
    required this.sessions,
  });
}

class ItemStat {
  final String name;
  final int quantity;
  final int revenue;
  const ItemStat(this.name, this.quantity, this.revenue);
}

class KindRevenue {
  /// اسم النوع: بلياردو، هوكي، بلايستيشن، كمبيوتر...
  final String label;
  final int revenue;
  const KindRevenue(this.label, this.revenue);
}

class BookingStat {
  final String resourceName;
  final int count;
  const BookingStat(this.resourceName, this.count);
}

class HourStat {
  final int hour; // 0..23
  final int sessions;
  const HourStat(this.hour, this.sessions);
}

class Report {
  final DateRange range;
  final ReportSummary summary;
  final List<DailySales> daily;
  final List<ResourceStat> topByRevenue;
  final List<ResourceStat> topByMinutes;
  final List<BookingStat> topByBookings;
  final List<ItemStat> topItemsByQuantity;
  final List<KindRevenue> revenueByKind;
  final List<HourStat> busiestHours;

  const Report({
    required this.range,
    required this.summary,
    required this.daily,
    required this.topByRevenue,
    required this.topByMinutes,
    required this.topByBookings,
    required this.topItemsByQuantity,
    required this.revenueByKind,
    required this.busiestHours,
  });
}
