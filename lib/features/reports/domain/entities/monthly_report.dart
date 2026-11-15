import '../../../expenses/domain/entities/expense.dart';
import 'report.dart' show ItemStat;

/// مجموع سحوبات شخص واحد في الشهر (المدير يسجّل اسم كل من سحب).
class WithdrawerTotal {
  final String name;
  final int count;
  final int amount;
  const WithdrawerTotal(this.name, this.count, this.amount);
}

/// فرق الجرد لصنف في الشهر. [difference] = الفعلي − المتوقع، فالسالب نقص
/// والموجب زيادة. [value] = الفرق × تكلفة القطعة الحالية للصنف.
class StockDifference {
  final String name;
  final int difference;
  final int unitCost;
  const StockDifference(this.name, this.difference, this.unitCost);

  int get value => difference * unitCost;
}

/// التقرير الشهري للمدير. كل المبالغ أعداد صحيحة بالليرة.
///
/// قواعد الحساب (متفق عليها):
///  - الإيراد: الفواتير المغلقة حسب **يوم العمل** الذي بدأ في الشهر.
///  - مشتريات البوفيه: الدفعات المسدّدة (`paid_at`) داخل الشهر، لا تاريخ الفاتورة.
///  - ربح التشغيل = الإيراد − (مشتريات البوفيه + صيانة + رواتب + مستلزمات).
///  - ثم يُطرح منه المسحوبات والاحتياطي للوصول إلى الصافي.
class MonthlyReport {
  final int year;
  final int month;

  final int invoiceCount;
  final int playRevenue;
  final int barRevenue;

  /// الحد الأدنى للفاتورة والتقريب (الفرق بين مجموع الفواتير ومجموع اللعب والبار).
  final int adjustments;
  final int totalRevenue;

  /// مشتريات البوفيه المسدّدة في الشهر.
  final int buffetPurchases;

  /// المصاريف المدخلة حسب النوع (بدون المحذوفة).
  final Map<ExpenseKind, int> expenses;

  /// سحوبات كل شخص (الأكبر أولًا).
  final List<WithdrawerTotal> withdrawers;

  /// ديون المشتريات غير المسدّدة حتى نهاية الشهر (معلومة فقط، لا تُخصم).
  final int unpaidPurchases;

  /// مجموع ما وُضع في الاحتياطي من البداية حتى نهاية الشهر.
  final int reserveBalance;

  final List<ItemStat> topItems;
  final List<StockDifference> stockDifferences;

  const MonthlyReport({
    required this.year,
    required this.month,
    required this.invoiceCount,
    required this.playRevenue,
    required this.barRevenue,
    required this.adjustments,
    required this.totalRevenue,
    required this.buffetPurchases,
    required this.expenses,
    required this.withdrawers,
    required this.unpaidPurchases,
    required this.reserveBalance,
    required this.topItems,
    required this.stockDifferences,
  });

  int expense(ExpenseKind kind) => expenses[kind] ?? 0;

  int get maintenance => expense(ExpenseKind.maintenance);
  int get salaries => expense(ExpenseKind.salaries);
  int get supplies => expense(ExpenseKind.supplies);
  int get withdrawals => expense(ExpenseKind.withdrawals);
  int get reserve => expense(ExpenseKind.reserve);

  /// مصاريف التشغيل: كل شيء ما عدا المسحوبات والاحتياطي.
  int get operatingExpenses =>
      buffetPurchases + maintenance + salaries + supplies;

  int get operatingProfit => totalRevenue - operatingExpenses;

  /// الصافي بعد المسحوبات والاحتياطي.
  int get netAfterDistributions => operatingProfit - withdrawals - reserve;

  /// صافي قيمة فروقات الجرد (سالب = نقص).
  int get stockDifferenceValue =>
      stockDifferences.fold<int>(0, (a, d) => a + d.value);

  /// لا فواتير ولا مصاريف ولا مشتريات ولا جرد في الشهر.
  bool get isEmpty =>
      invoiceCount == 0 &&
      buffetPurchases == 0 &&
      expenses.values.every((v) => v == 0) &&
      stockDifferences.isEmpty;
}
