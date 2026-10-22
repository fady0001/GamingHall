import '../entities/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> load();
  Stream<AppSettings> watch();
  Future<void> save(AppSettings settings);
}
