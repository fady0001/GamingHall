import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/settings/data/settings_store.dart';
import '../database/app_database.dart';

enum BackupTrigger { manual, automatic }

class BackupResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;

  const BackupResult.success(this.filePath)
      : success = true,
        errorMessage = null;

  const BackupResult.failure(this.errorMessage)
      : success = false,
        filePath = null;
}

/// نسخ احتياطي واستعادة لقاعدة SQLite. النسخة تتم بـ VACUUM INTO فتكون
/// متسقة حتى والتطبيق يعمل. تُحفظ تلقائيًا كل 24 ساعة وتُبقي آخر 30 نسخة.
///
/// - مجلد النسخ الذي يختاره المدير يُحفظ في الإعدادات ويُستخدم للنسخ التلقائي.
/// - لكل نسخة ملف بجانبها `.sha256` فيه بصمة الملف؛ تُفحص قبل أي استعادة.
/// - **الأرشيف**: قاعدة البيانات تبقى ملفًا واحدًا. كل [archiveEveryMonths]
///   (شهر واحد) تُحفظ نسخة كاملة منفصلة في مجلد `Archive` بجانب النسخ ولا تُحذف
///   أبدًا (النسخ التلقائية العادية تبقى آخر 30 فقط). وللمدير زر "أرشفة الآن".
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const int _retentionCount = 30;
  static const Duration _autoInterval = Duration(hours: 24);
  static const Duration _checkInterval = Duration(minutes: 30);
  static const String _filePrefix = 'gaming_hall_backup_';
  static const String _fileExt = '.db';

  static const String _kFolderKey = 'backup_folder';
  static const String _kArchiveKey = 'last_archive_at';
  static const String _archiveDirName = 'Archive';

  /// كل كم شهرًا تُحفظ نسخة أرشيف كاملة تلقائيًا (1 = كل شهر).
  static const int archiveEveryMonths = 1;
  static const String _checksumExt = '.sha256';

  Timer? _timer;

  /// المجلد الذي اختاره المدير للنسخ (أو null = الافتراضي).
  Future<String?> savedBackupFolder() async {
    try {
      final v = await SettingsStore.readValue(_db.raw, _kFolderKey);
      return (v == null || v.trim().isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  /// يحفظ مجلد النسخ (null يعيده للافتراضي).
  Future<void> setBackupFolder(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await SettingsStore.deleteValue(_db.raw, _kFolderKey);
    } else {
      await Directory(path).create(recursive: true);
      await SettingsStore.writeValue(_db.raw, _kFolderKey, path);
    }
  }

  /// المجلد المستخدم فعليًا: المحفوظ إن وُجد وصلح، وإلا الافتراضي.
  Future<Directory> activeBackupDirectory() async {
    final saved = await savedBackupFolder();
    if (saved != null) {
      try {
        final dir = Directory(saved);
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      } catch (_) {
        // المجلد غير متاح (فلاشة مفصولة مثلًا): نرجع للافتراضي هذه المرة.
      }
    }
    return defaultBackupDirectory();
  }

  Future<String> _sha256Of(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  /// يفحص سلامة نسخة بمقارنتها ببصمتها. يعيد null إن كانت سليمة أو لا بصمة
  /// لها (نسخ قديمة)، أو نص المشكلة.
  Future<String?> verifyChecksum(String backupPath) async {
    final sidecar = File('$backupPath$_checksumExt');
    if (!await sidecar.exists()) return null;
    try {
      final expected = (await sidecar.readAsString()).trim().split(RegExp(r'\s+')).first;
      final actual = await _sha256Of(backupPath);
      if (expected.toLowerCase() != actual.toLowerCase()) {
        return 'فشل فحص سلامة النسخة (checksum): الملف تالف أو تم تعديله.';
      }
      return null;
    } catch (e) {
      return 'تعذّر فحص سلامة النسخة: $e';
    }
  }

  Future<Directory> defaultBackupDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'GamingHall', 'Backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<DateTime?> lastBackupTime([String? folder]) async {
    final dir = Directory(folder ?? (await activeBackupDirectory()).path);
    if (!await dir.exists()) return null;
    DateTime? latest;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(_filePrefix) || !name.endsWith(_fileExt)) continue;
      final modified = (await entity.stat()).modified;
      if (latest == null || modified.isAfter(latest)) latest = modified;
    }
    return latest;
  }

  Future<BackupResult> runBackup({
    required BackupTrigger trigger,
    String? folderPath,
  }) async {
    try {
      if (!_db.isOpen) {
        return const BackupResult.failure('قاعدة البيانات غير مفتوحة.');
      }
      final folder = folderPath ?? (await activeBackupDirectory()).path;
      await Directory(folder).create(recursive: true);

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final target = p.join(folder, '$_filePrefix$stamp$_fileExt');
      await _db.exportTo(target);

      // بصمة السلامة بجانب النسخة.
      final hash = await _sha256Of(target);
      await File('$target$_checksumExt')
          .writeAsString('$hash  ${p.basename(target)}\n', flush: true);

      if (trigger == BackupTrigger.automatic) await _enforceRetention(folder);
      return BackupResult.success(target);
    } catch (e) {
      return BackupResult.failure('فشل إنشاء النسخة الاحتياطية: $e');
    }
  }

  Future<void> _enforceRetention(String folder) async {
    final files = <File>[];
    await for (final entity in Directory(folder).list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith(_filePrefix) && name.endsWith(_fileExt)) {
        files.add(entity);
      }
    }
    if (files.length <= _retentionCount) return;
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files.take(files.length - _retentionCount)) {
      try {
        await f.delete();
        final sidecar = File('${f.path}$_checksumExt');
        if (await sidecar.exists()) await sidecar.delete();
      } catch (_) {}
    }
  }

  Future<void> _autoIfDue() async {
    final last = await lastBackupTime();
    if (last == null || DateTime.now().difference(last) >= _autoInterval) {
      await runBackup(trigger: BackupTrigger.automatic);
    }
    await _archiveIfDue();
  }

  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final day = d.day > 28 ? 28 : d.day;
    return DateTime(year, month, day, d.hour, d.minute);
  }

  /// وقت آخر أرشفة (تلقائية أو يدوية)، أو null إن لم تحدث بعد.
  Future<DateTime?> lastArchiveTime() async {
    try {
      final raw = await SettingsStore.readValue(_db.raw, _kArchiveKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// أرشفة يدوية الآن (زر المدير). عند نجاحها يبدأ عدّ الشهر التلقائي من جديد.
  Future<BackupResult> archiveNow() async {
    final result = await runArchive();
    if (result.success) {
      try {
        await SettingsStore.writeValue(
            _db.raw, _kArchiveKey, DateTime.now().toIso8601String());
      } catch (_) {}
    }
    return result;
  }

  /// أول تشغيل: يبدأ عدّاد الأرشيف من الآن. بعدها ينشئ أرشيفًا كل
  /// [archiveEveryMonths] أشهر. الأرشيف نسخة كاملة، لا يُحذف تلقائيًا.
  Future<void> _archiveIfDue() async {
    try {
      final raw = await SettingsStore.readValue(_db.raw, _kArchiveKey);
      final now = DateTime.now();
      final last = raw == null ? null : DateTime.tryParse(raw);
      if (last == null) {
        await SettingsStore.writeValue(_db.raw, _kArchiveKey, now.toIso8601String());
        return;
      }
      if (now.isBefore(_addMonths(last, archiveEveryMonths))) return;
      final result = await runArchive();
      if (result.success) {
        await SettingsStore.writeValue(_db.raw, _kArchiveKey, now.toIso8601String());
      }
    } catch (_) {
      // نعيد المحاولة في الفحص القادم.
    }
  }

  /// ينشئ نسخة أرشيف كاملة الآن في `<مجلد النسخ>/Archive` (لا تُحذف تلقائيًا).
  Future<BackupResult> runArchive() async {
    try {
      if (!_db.isOpen) return const BackupResult.failure('قاعدة البيانات غير مفتوحة.');
      final base = (await activeBackupDirectory()).path;
      final folder = p.join(base, _archiveDirName);
      await Directory(folder).create(recursive: true);

      final d = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final target = p.join(
          folder, 'GamingHall_archive_${d.year}-${two(d.month)}-${two(d.day)}$_fileExt');
      await _db.exportTo(target);
      final hash = await _sha256Of(target);
      await File('$target$_checksumExt')
          .writeAsString('$hash  ${p.basename(target)}\n', flush: true);
      return BackupResult.success(target);
    } catch (e) {
      return BackupResult.failure('فشل إنشاء نسخة الأرشيف: $e');
    }
  }

  void startAutoBackup() {
    stopAutoBackup();
    unawaited(_autoIfDue());
    _timer = Timer.periodic(_checkInterval, (_) => _autoIfDue());
  }

  void stopAutoBackup() {
    _timer?.cancel();
    _timer = null;
  }

  /// يستبدل قاعدة البيانات الحالية بنسخة احتياطية. بعد النجاح يجب إعادة تشغيل
  /// التطبيق (يتولاه المستدعي). تُحفظ نسخة أمان من البيانات الحالية قبل
  /// الاستبدال بجانب الملف الأصلي باسم `.before_restore`.
  Future<BackupResult> restoreFrom(String backupPath) async {
    try {
      if (!await File(backupPath).exists()) {
        return const BackupResult.failure('ملف النسخة الاحتياطية غير موجود.');
      }
      final checksumProblem = await verifyChecksum(backupPath);
      if (checksumProblem != null) return BackupResult.failure(checksumProblem);
      final problem = await AppDatabase.validateBackupFile(backupPath);
      if (problem != null) return BackupResult.failure(problem);

      stopAutoBackup();
      final livePath = _db.path;
      await _db.close();

      final safety = '$livePath.before_restore';
      if (await File(livePath).exists()) {
        await File(livePath).copy(safety);
      }
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final extra = File('$livePath$suffix');
        if (await extra.exists()) await extra.delete();
      }
      await File(backupPath).copy(livePath);
      return const BackupResult.success(null);
    } catch (e) {
      return BackupResult.failure('فشلت عملية الاستعادة: $e');
    }
  }
}
