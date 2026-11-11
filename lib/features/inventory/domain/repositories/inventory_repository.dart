import '../../../../core/domain/value_objects/money.dart';
import '../../../menu/domain/entities/menu_category.dart';
import '../entities/inventory_models.dart';

abstract class InventoryRepository {
  /// كل الأصناف الفعّالة (تُباع أو لا تُباع) مع كمياتها الحالية.
  Stream<List<StockRow>> watchStock();

  /// أحدث فواتير المشتريات (الأحدث أولًا) مع أسطرها ودفعاتها.
  Stream<List<PurchaseInvoice>> watchPurchaseInvoices({int limit = 200});

  /// جرد يوم معيّن (yyyy-MM-dd).
  Stream<List<CountRecord>> watchCounts(String date);

  /// سجل التعديلات اليدوية على المخزون (الأحدث أولًا).
  Stream<List<StockAdjustment>> watchAdjustments({int limit = 300});

  /// ينشئ فاتورة مشتريات (id == null) أو يعدّل فاتورة موجودة. القطع تدخل
  /// المخزون، وتُحدَّث تكلفة القطعة. يعيد رقم الفاتورة.
  Future<int> saveInvoice(PurchaseInvoiceInput input);

  /// حذف فاتورة كاملة: تُسحب كل قطعها من المخزون وتُحذف دفعاتها.
  Future<void> deleteInvoice(int invoiceId);

  /// تسديد دفعة على فاتورة (لا تتجاوز المتبقي).
  Future<void> addPayment({
    required int invoiceId,
    required Money amount,
    DateTime? paidAt,
    String? note,
  });

  Future<void> deletePayment(int paymentId);

  /// تعديل يدوي للكمية (زيادة / نقص / ضبط على رقم) مع سبب إلزامي.
  Future<void> adjustStock({
    required int itemId,
    required StockAdjustMode mode,
    required int quantity,
    required String reason,
  });

  /// صنف جديد من شاشة الشراء: لا يُباع (لا يظهر في قائمة المشتريات).
  /// يعيد رقم الصنف.
  Future<int> createStockItem({
    required String name,
    required MenuCategory category,
  });

  /// تفعيل/إيقاف تتبّع الصنف، حدّ التنبيه، وهل يُباع (مع سعر البيع).
  Future<void> updateStockSettings({
    required int itemId,
    required bool trackStock,
    required int minStock,
    required bool isSellable,
    Money? price,
  });

  /// يحفظ جرد [date]. يعيد عدد الأصناف المحفوظة. إعادة جرد صنف في نفس اليوم
  /// تستبدل جرده السابق. الفرق بين الفعلي والمتوقع يُسوّى في المخزون مباشرة.
  Future<int> saveCounts(String date, List<CountEntry> entries);
}
