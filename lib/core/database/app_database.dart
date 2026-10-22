import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../constants/app_info.dart';
import 'schema.dart';


class AppDatabase {
  AppDatabase._(this._db, this.path);

  final Database _db;
  final String path;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool _closed = false;

  static Future<String> defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, AppInfo.databaseFileName);
    await _migrateLegacyFile(dir.path, path);
    return path;
  }

  /// كان ملف القاعدة اسمه `game_lounge.db`. إن وُجد ولم يوجد الملف الجديد
  /// ننقله (مع ملفات الجورنال إن وُجدت) حتى لا تضيع بيانات المستخدمين.
  static Future<void> _migrateLegacyFile(String dir, String newPath) async {
    if (await File(newPath).exists()) return;
    final oldPath = p.join(dir, 'game_lounge.db');
    if (!await File(oldPath).exists()) return;
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final old = File('$oldPath$suffix');
      if (await old.exists()) await old.rename('$newPath$suffix');
    }
  }

  static Future<AppDatabase> open({String? path}) async {
    sqfliteFfiInit();
    final dbPath = path ?? await defaultPath();
    await Directory(p.dirname(dbPath)).create(recursive: true);
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: AppSchema.version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => AppSchema.create(db),
        onUpgrade: AppSchema.upgrade,
      ),
    );
    return AppDatabase._(db, dbPath);
  }

  /// للقراءة فقط (الاستعلامات). الكتابة عبر [write].
  Database get raw => _db;

  bool get isOpen => !_closed;

  /// ينفّذ كتابة داخل معاملة واحدة ثم يُبلّغ المراقبين.
  Future<T> write<T>(Future<T> Function(Transaction txn) action) async {
    final result = await _db.transaction(action);
    notifyChanged();
    return result;
  }

  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// بثّ حيّ لنتيجة استعلام: يصدر فورًا ثم كلما تغيّرت القاعدة.
  Stream<T> watch<T>(Future<T> Function() load) {
    late final StreamController<T> controller;
    StreamSubscription<void>? subscription;
    var sequence = 0;

    Future<void> emitCurrent() async {
      final mine = ++sequence;
      try {
        final value = await load();
        if (!controller.isClosed && mine == sequence) controller.add(value);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = _changes.stream.listen((_) => emitCurrent());
        emitCurrent();
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// نسخة متسقة من القاعدة الحالية (تعمل والتطبيق مفتوح).
  Future<void> exportTo(String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) await target.delete();
    final escaped = targetPath.replaceAll("'", "''");
    await _db.execute("VACUUM INTO '$escaped'");
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
    await _changes.close();
  }

  /// يتحقق أن الملف قاعدة بيانات سليمة تخصّ هذا التطبيق. يعيد رسالة الخطأ أو null.
  static Future<String?> validateBackupFile(String filePath) async {
    sqfliteFfiInit();
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(
        filePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        return 'ملف النسخة الاحتياطية تالف.';
      }
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((r) => r['name'] as String).toSet();
      const required = {
        'settings',
        'manager_account',
        'resources',
        'menu_items',
        'work_days',
        'invoices',
        'play_lines',
        'item_lines',
        'bookings',
      };
      if (!names.containsAll(required)) {
        return 'هذا الملف ليس نسخة احتياطية من هذا التطبيق.';
      }
      return null;
    } catch (e) {
      return 'تعذّرت قراءة الملف: $e';
    } finally {
      await db?.close();
    }
  }
}
