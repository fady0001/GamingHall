import '../../../core/database/app_database.dart';
import '../domain/entities/app_settings.dart';
import '../domain/repositories/settings_repository.dart';
import 'settings_store.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final AppDatabase _db;
  SettingsRepositoryImpl(this._db);

  @override
  Future<AppSettings> load() => SettingsStore.readSettings(_db.raw);

  @override
  Stream<AppSettings> watch() => _db.watch(load);

  @override
  Future<void> save(AppSettings settings) async {
    if (settings.loungeName.trim().isEmpty) {
      throw ArgumentError('اسم الصالة مطلوب');
    }
    if (settings.minimumInvoice.amount < 0) {
      throw ArgumentError('الحد الأدنى للفاتورة غير صالح');
    }
    await _db.write((txn) => SettingsStore.writeSettings(txn, settings));
  }
}
