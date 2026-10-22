import '../../../../core/domain/entities/billing_policy.dart';
import '../../../../core/domain/usecases/billing.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../menu/domain/entities/menu_category.dart';
import '../../../resources/domain/entities/resource_kind.dart';

enum InvoiceStatus { open, closed }

/// خط لعب: جهاز/طاولة بوقت مفتوح. سعر الساعة "لقطة" وقت البدء، فتغيير الأسعار
/// لاحقًا لا يؤثر على لعب جارٍ أو فاتورة مغلقة.
class PlayLine {
  final int id;
  final int invoiceId;
  final int resourceId;
  final String resourceName;
  final ResourceKind resourceKind;

  /// مفتاح النوع وقت اللعب: اسم نوع الطاولة (بلياردو...) أو اسم الفئة.
  final String typeKey;
  final int playerCount;
  final Money hourlyRate;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? billedMinutes;
  final Money? charge;

  /// null = وقت مفتوح. غير ذلك = وقت محدد بهذا العدد من الدقائق.
  final int? plannedMinutes;

  const PlayLine({
    required this.id,
    required this.invoiceId,
    required this.resourceId,
    required this.resourceName,
    required this.resourceKind,
    String? typeKey,
    required this.playerCount,
    required this.hourlyRate,
    required this.startedAt,
    this.endedAt,
    this.billedMinutes,
    this.charge,
    this.plannedMinutes,
  }) : typeKey = typeKey ?? '';

  bool get isRunning => endedAt == null;

  bool get isFixed => plannedMinutes != null;

  String get typeLabel => labelForTypeKey(typeKey.isEmpty ? resourceKind.name : typeKey);

  /// لحظة انتهاء الوقت المحدد (null للوقت المفتوح).
  DateTime? get plannedEnd =>
      plannedMinutes == null ? null : startedAt.add(Duration(minutes: plannedMinutes!));

  /// المتبقي من الوقت المحدد (صفر إن انتهى، null للمفتوح).
  Duration? remainingAt(DateTime now) {
    final end = plannedEnd;
    if (end == null) return null;
    final d = end.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  bool isExpiredAt(DateTime now) {
    final end = plannedEnd;
    return isRunning && end != null && !now.isBefore(end);
  }

  Duration elapsedAt(DateTime now) {
    var end = endedAt ?? now;
    // الوقت المحدد لا يتجاوز نهايته أبدًا (حتى لو تأخر إيقافه).
    final planned = plannedEnd;
    if (endedAt == null && planned != null && end.isAfter(planned)) end = planned;
    final d = end.difference(startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  int minutesAt(DateTime now) =>
      isRunning ? billedMinutesFor(elapsedAt(now)) : (billedMinutes ?? 0);

  Money chargeAt(DateTime now) {
    if (!isRunning) return charge ?? Money.zero;
    return chargeForMinutes(hourlyRate: hourlyRate, minutes: minutesAt(now));
  }
}

class ItemLine {
  final int id;
  final int invoiceId;
  final int menuItemId;
  final String name;
  final MenuCategory category;
  final Money unitPrice;
  final int quantity;

  const ItemLine({
    required this.id,
    required this.invoiceId,
    required this.menuItemId,
    required this.name,
    required this.category,
    required this.unitPrice,
    required this.quantity,
  });

  Money get total => unitPrice * quantity;
}

/// الفاتورة: كل ما يفعله ويشتريه زبون (أو مجموعة أصدقاء بحساب واحد).
class Invoice {
  final int id;
  final String customerName;
  final int dayId;
  final InvoiceStatus status;
  final DateTime createdAt;
  final DateTime? closedAt;
  final List<PlayLine> playLines;
  final List<ItemLine> itemLines;

  /// المجاميع المثبّتة عند الإغلاق (null للفاتورة المفتوحة).
  final InvoiceTotals? settledTotals;

  const Invoice({
    required this.id,
    required this.customerName,
    required this.dayId,
    required this.status,
    required this.createdAt,
    required this.playLines,
    required this.itemLines,
    this.closedAt,
    this.settledTotals,
  });

  bool get isOpen => status == InvoiceStatus.open;

  List<PlayLine> get runningLines =>
      playLines.where((l) => l.isRunning).toList();

  bool get isEmpty => playLines.isEmpty && itemLines.isEmpty;

  /// المجاميع: المثبّتة إن كانت مغلقة، وإلا محسوبة حيًا عند [now].
  InvoiceTotals totalsAt(DateTime now, BillingPolicy policy) {
    if (settledTotals != null) return settledTotals!;
    return computeInvoiceTotals(
      playCharges: [for (final l in playLines) l.chargeAt(now)],
      itemTotals: [for (final i in itemLines) i.total],
      policy: policy,
    );
  }

  /// آخر وقت نشاط (للترتيب).
  DateTime get sortTime => closedAt ?? createdAt;
}
