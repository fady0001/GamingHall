import 'package:flutter/material.dart';

/// تصنيف صنف المنيو (يُخزَّن بالاسم).
enum MenuCategory { food, coldDrinks, hotDrinks, hookah, other }

extension MenuCategoryX on MenuCategory {
  String get label {
    switch (this) {
      case MenuCategory.food:
        return 'مأكولات';
      case MenuCategory.coldDrinks:
        return 'مشروبات باردة';
      case MenuCategory.hotDrinks:
        return 'مشروبات ساخنة';
      case MenuCategory.hookah:
        return 'أراكيل';
      case MenuCategory.other:
        return 'أخرى';
    }
  }

  IconData get icon {
    switch (this) {
      case MenuCategory.food:
        return Icons.fastfood_rounded;
      case MenuCategory.coldDrinks:
        return Icons.local_drink_rounded;
      case MenuCategory.hotDrinks:
        return Icons.coffee_rounded;
      case MenuCategory.hookah:
        return Icons.smoking_rooms_rounded;
      case MenuCategory.other:
        return Icons.category_rounded;
    }
  }
}

MenuCategory menuCategoryFromName(String name) {
  for (final c in MenuCategory.values) {
    if (c.name == name) return c;
  }
  return MenuCategory.other;
}
