import '../entities/menu_item_entity.dart';

abstract class MenuRepository {
  Stream<List<MenuItemEntity>> watchAll();
  Future<MenuItemEntity> add(MenuItemEntity item);
  Future<MenuItemEntity> update(MenuItemEntity item);

  /// إخفاء من المنيو (لا حذف فعلي).
  Future<void> remove(int id);
}
