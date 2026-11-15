import '../../../../core/domain/value_objects/money.dart';
import '../entities/buffet_payment.dart';
import '../entities/expense.dart';

/// مصاريف الصالة (للمدير فقط). الحذف "منطقي": يختفي المصروف من القوائم
/// والتقارير ويبقى أثره في سجل التعديلات.
abstract class ExpenseRepository {
  /// مصاريف شهر معيّن ([month] من 1 إلى 12)، الأحدث أولًا.
  Stream<List<Expense>> watchMonth(int year, int month);

  /// دفعات مشتريات البوفيه المسدَّدة في شهر معيّن (حسب تاريخ الدفع)، الأحدث
  /// أولًا. للعرض فقط: لا إضافة ولا تعديل ولا حذف من هنا.
  Stream<List<BuffetPayment>> watchBuffetPayments(int year, int month);

  /// ما بقي غير مسدَّد من فواتير المشتريات حتى نهاية الشهر المعروض (نفس حساب
  /// "ديون المشتريات" في التقرير الشهري).
  Stream<Money> watchBuffetUnpaid(int year, int month);

  /// سجل التعديلات (الأحدث أولًا).
  Stream<List<ExpenseLogEntry>> watchLog({int limit = 300});

  /// أسماء من سحبوا سابقًا (الأحدث أولًا) لاقتراحها عند تسجيل سحب جديد.
  Stream<List<String>> watchWithdrawerNames();

  /// يضيف مصروفًا ويعيد رقمه.
  Future<int> add(ExpenseInput input);

  /// يعدّل مصروفًا. إن لم يتغيّر شيء لا يُكتب شيء ولا يُسجَّل في السجل.
  Future<void> update(int id, ExpenseInput input);

  /// حذف منطقي.
  Future<void> delete(int id);
}
