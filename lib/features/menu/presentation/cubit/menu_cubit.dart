import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/menu_category.dart';
import '../../domain/entities/menu_item_entity.dart';
import '../../domain/repositories/menu_repository.dart';

class MenuState {
  final List<MenuItemEntity> items;
  final bool isLoading;
  const MenuState({this.items = const [], this.isLoading = true});

  List<MenuItemEntity> byCategory(MenuCategory c) =>
      items.where((i) => i.category == c).toList();
}

class MenuCubit extends Cubit<MenuState> {
  final MenuRepository _repository;

  /// هل المستخدم الحالي مدير؟ الإضافة مسموحة للجميع، أما التعديل والحذف
  /// فللمدير فقط. نتحقق هنا أيضًا (لا في الواجهة فقط) حتى لا يتجاوز الموظفُ
  /// القيد بأي شاشة أخرى.
  final bool Function() _isManager;
  StreamSubscription<List<MenuItemEntity>>? _subscription;

  MenuCubit(this._repository, {bool Function()? isManager})
      : _isManager = isManager ?? (() => true),
        super(const MenuState()) {
    _subscription = _repository.watchAll().listen(
          (items) => emit(MenuState(items: items, isLoading: false)),
        );
  }

  Future<MenuItemEntity> add(MenuItemEntity item) => _repository.add(item);
  Future<MenuItemEntity> update(MenuItemEntity item) {
    _requireManager();
    return _repository.update(item);
  }

  Future<void> remove(int id) {
    _requireManager();
    return _repository.remove(id);
  }

  void _requireManager() {
    if (!_isManager()) {
      throw StateError('تعديل أو حذف الأصناف من صلاحيات المدير فقط');
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
