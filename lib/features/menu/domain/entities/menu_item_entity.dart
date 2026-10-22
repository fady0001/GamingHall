import '../../../../core/domain/value_objects/money.dart';
import 'menu_category.dart';

/// صنف في المنيو (أكلة، مشروب، أركيلة...). لا يوجد تتبّع مخزون: كل صنف
/// "مفعّل" يمكن بيعه. التعطيل بدل الحذف حتى تبقى الفواتير القديمة سليمة.
class MenuItemEntity {
  final int id;
  final String name;
  final MenuCategory category;
  final Money price;
  final bool isActive;

  const MenuItemEntity({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.isActive = true,
  });

  MenuItemEntity copyWith({
    String? name,
    MenuCategory? category,
    Money? price,
    bool? isActive,
  }) {
    return MenuItemEntity(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
    );
  }
}
