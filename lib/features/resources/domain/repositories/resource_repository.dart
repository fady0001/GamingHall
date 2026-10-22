import '../entities/game_resource.dart';
import '../entities/resource_kind.dart';
import '../entities/resource_type.dart';

abstract class ResourceRepository {
  /// كل الموارد غير المخفية (بما فيها خارج الخدمة)، مرتبة بالنوع ثم الاسم.
  Stream<List<GameResource>> watchAll();

  Future<GameResource> add(GameResource resource);
  Future<GameResource> update(GameResource resource);
  /// يرمي [StateError] عند الإخراج من الخدمة إن كان عليه لعب جارٍ أو حجز.
  Future<void> setOutOfService(int id, bool value);

  /// إخفاء نهائي. يرمي [StateError] إن كان عليه لعب جارٍ أو حجز.
  Future<void> remove(int id);

  /// سبب منع حذف الجهاز ([forDelete] = true) أو إخراجه من الخدمة (false):
  /// لعب جارٍ أو حجز قائم عليه. null = مسموح. (الفحص نفسه يُعاد داخل
  /// [remove] و[setOutOfService] ضمن المعاملة، فلا يمكن تجاوزه.)
  Future<String?> blockReason(int id, {required bool forDelete});

  // ---- أنواع الطاولات ----

  /// كل الأنواع التي أضافها المدير (فارغة في البداية).
  Stream<List<ResourceType>> watchTypes();

  /// يضيف نوعًا جديدًا. يرمي [StateError] إن كان الاسم موجودًا.
  Future<ResourceType> addType(String name, {ResourceKind kind = ResourceKind.table});

  /// يغيّر اسم نوع، وتتبعه كل الطاولات من هذا النوع. يرمي [StateError] إن كان
  /// الاسم الجديد موجودًا.
  Future<void> renameType(int id, String newName);

  /// يحذف نوعًا إن لم تستعمله أي طاولة.
  Future<void> removeType(int id);
}
