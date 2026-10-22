import '../entities/invoice.dart';

class InvoiceSearchFilter {
  /// تاريخ ميلادي محدد (يطابق تاريخ إنشاء الفاتورة).
  final DateTime? date;

  /// يوم عمل محدد.
  final int? dayId;

  /// اسم الزبون أو رقم الفاتورة (`12` أو `#12`).
  final String query;

  final bool closedOnly;

  const InvoiceSearchFilter({
    this.date,
    this.dayId,
    this.query = '',
    this.closedOnly = false,
  });
}

abstract class InvoiceRepository {
  /// الفواتير المفتوحة حاليًا، الأحدث أولًا.
  Stream<List<Invoice>> watchOpen();

  /// كل فواتير يوم عمل (مفتوحة ومغلقة).
  Stream<List<Invoice>> watchByDay(int dayId);

  Stream<Invoice?> watchById(int id);
  Future<Invoice?> getById(int id);

  Future<Invoice> create(String customerName);

  /// يبدأ لعبًا على جهاز ضمن فاتورة مفتوحة. [plannedMinutes] = null: وقت مفتوح
  /// يوقفه الموظف. غير ذلك: وقت محدد ينتهي تلقائيًا بعد هذه الدقائق.
  Future<void> startPlay({
    required int invoiceId,
    required int resourceId,
    required int playerCount,
    int? plannedMinutes,
  });

  /// ينهي كل وقت محدد انتهى (عند نهايته بالضبط لا الآن) ويعيد الخطوط المنتهية
  /// ليُنبَّه الموظف. آمن للاستدعاء المتكرر.
  Future<List<PlayLine>> endExpiredFixedLines();

  /// تمديد وقت محدد بـ [extraMinutes]: إن كان ما زال جاريًا يُزاد وقته، وإن كان
  /// قد انتهى يبدأ خط جديد من الآن بنفس الجهاز والسعر (فلا يُحسب وقت الانتظار).
  Future<void> extendPlay({required int playLineId, required int extraMinutes});

  /// يوقف الوقت لخط لعب واحد ويثبّت أجره.
  Future<void> stopPlay(int playLineId);

  /// يضيف صنفًا (أو يزيد كميته إن كان موجودًا بنفس السعر).
  Future<void> addItem({
    required int invoiceId,
    required int menuItemId,
    required int quantity,
  });

  /// يضبط كمية صنف؛ الصفر يحذفه من الفاتورة.
  Future<void> setItemQuantity(int itemLineId, int quantity);

  /// "الحساب": يوقف أي لعب جارٍ، يحسب المجاميع بقواعد التسعير، ويغلق الفاتورة.
  Future<Invoice> checkout(int invoiceId);

  /// يحذف فاتورة مفتوحة فارغة تمامًا (أُنشئت بالخطأ). غير ممكن بعد أي لعب أو طلب.
  Future<void> deleteIfEmpty(int invoiceId);

  Future<List<Invoice>> search(InvoiceSearchFilter filter, {int limit = 300});
}
