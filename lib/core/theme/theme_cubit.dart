import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/settings/data/settings_store.dart';
import '../database/app_database.dart';

/// وضع الواجهة: الحالة = true للوضع الداكن، false للفاتح. يُحفظ الاختيار في
/// جدول settings فيبقى بعد إعادة التشغيل.
class ThemeCubit extends Cubit<bool> {
  ThemeCubit(this._db) : super(true) {
    _load();
  }

  final AppDatabase _db;
  static const String _key = 'theme_mode';

  Future<void> _load() async {
    try {
      final v = await SettingsStore.readValue(_db.raw, _key);
      if (!isClosed && v == 'light') emit(false);
    } catch (_) {}
  }

  Future<void> toggle() async {
    final next = !state;
    emit(next);
    try {
      await SettingsStore.writeValue(_db.raw, _key, next ? 'dark' : 'light');
    } catch (_) {}
  }
}
