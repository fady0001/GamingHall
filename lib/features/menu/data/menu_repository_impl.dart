import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/domain/value_objects/money.dart';
import '../domain/entities/menu_category.dart';
import '../domain/entities/menu_item_entity.dart';
import '../domain/repositories/menu_repository.dart';

MenuItemEntity menuItemFromRow(Map<String, Object?> r) => MenuItemEntity(
      id: r['id'] as int,
      name: r['name'] as String,
      category: menuCategoryFromName(r['category'] as String),
      price: Money(r['price'] as int),
      isActive: dbBool(r['is_active']),
    );

class MenuRepositoryImpl implements MenuRepository {
  final AppDatabase _db;
  MenuRepositoryImpl(this._db);

  Future<List<MenuItemEntity>> _loadAll() async {
    final rows = await _db.raw.query(
      'menu_items',
      where: 'is_active = 1',
      orderBy: 'category ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(menuItemFromRow).toList();
  }

  @override
  Stream<List<MenuItemEntity>> watchAll() => _db.watch(_loadAll);

  void _validate(MenuItemEntity item) {
    if (item.name.trim().isEmpty) throw ArgumentError('اسم الصنف مطلوب');
    if (item.price.amount <= 0) throw ArgumentError('أدخل سعرًا صحيحًا للصنف');
  }

  Never _rethrowFriendly(Object e, String name) {
    if (isUniqueViolation(e)) {
      throw StateError('يوجد صنف بنفس الاسم "${name.trim()}" في المنيو');
    }
    throw e;
  }

  @override
  Future<MenuItemEntity> add(MenuItemEntity item) async {
    _validate(item);
    try {
      final id = await _db.write((txn) => txn.insert('menu_items', {
            'name': item.name.trim(),
            'category': item.category.name,
            'price': item.price.amount,
            'is_active': 1,
            'created_at': dbTime(DateTime.now()),
          }));
      final rows =
          await _db.raw.query('menu_items', where: 'id = ?', whereArgs: [id]);
      return menuItemFromRow(rows.first);
    } catch (e) {
      _rethrowFriendly(e, item.name);
    }
  }

  @override
  Future<MenuItemEntity> update(MenuItemEntity item) async {
    _validate(item);
    try {
      await _db.write((txn) => txn.update(
            'menu_items',
            {
              'name': item.name.trim(),
              'category': item.category.name,
              'price': item.price.amount,
            },
            where: 'id = ?',
            whereArgs: [item.id],
          ));
      final rows = await _db.raw
          .query('menu_items', where: 'id = ?', whereArgs: [item.id]);
      return menuItemFromRow(rows.first);
    } catch (e) {
      _rethrowFriendly(e, item.name);
    }
  }

  @override
  Future<void> remove(int id) async {
    await _db.write((txn) => txn.update(
          'menu_items',
          {'is_active': 0},
          where: 'id = ?',
          whereArgs: [id],
        ));
  }
}
