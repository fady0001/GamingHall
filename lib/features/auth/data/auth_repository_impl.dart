import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_utils.dart';
import '../../../core/security/password_hasher.dart';
import '../../settings/data/settings_store.dart';
import '../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AppDatabase _db;
  AuthRepositoryImpl(this._db);

  static const String _kFailedCount = 'auth_failed_count';
  static const String _kLockedUntil = 'auth_locked_until';
  static const int _freeAttempts = 5;

  // ---- تسلسل عمليات المصادقة ----
  //
  // كل عملية تحقق (دخول / تغيير كلمة سر / استرداد) تُنفَّذ بعد انتهاء التي
  // قبلها. بدون ذلك يمكن إطلاق عدة محاولات متوازية قبل أن يُسجَّل أي فشل،
  // فيتجاوز المهاجم حدّ المحاولات المسموحة قبل القفل المؤقت.
  Future<void> _authQueue = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _authQueue;
    // الذيل لا يفشل أبدًا، فلا يتعطل الطابور بسبب خطأ في عملية سابقة.
    _authQueue = completer.future.then<void>((_) {}, onError: (_) {});
    previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<Map<String, Object?>?> _account(DatabaseExecutor ex) async {
    final rows = await ex.query('manager_account', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<bool> hasManagerAccount() async => (await _account(_db.raw)) != null;

  @override
  Future<String?> managerUsername() async =>
      (await _account(_db.raw))?['username'] as String?;

  @override
  Future<String> createManagerAccount({
    required String username,
    required String password,
  }) async {
    final name = username.trim();
    if (name.length < 3) {
      throw const AuthException('اسم المستخدم يجب ألا يقل عن 3 أحرف');
    }
    final passwordError = validatePassword(password);
    if (passwordError != null) throw AuthException(passwordError);

    final recoveryCode = generateRecoveryCode();
    // التجزئتان مستقلتان فتُحسبان معًا في Isolate منفصل لكل منهما، بدل
    // الانتظار لواحدة ثم الأخرى. لا يتغير أي شيء في قوة التجزئة.
    final hashes = await Future.wait<String>([
      PasswordHasher.hash(password),
      PasswordHasher.hash(normalizeRecoveryCode(recoveryCode)),
    ]);
    final passwordHash = hashes[0];
    final recoveryHash = hashes[1];
    final now = dbTime(DateTime.now());

    await _db.write((txn) async {
      if (await _account(txn) != null) {
        throw const AuthException('حساب المدير موجود مسبقًا');
      }
      await txn.insert('manager_account', {
        'id': 1,
        'username': name,
        'password_hash': passwordHash,
        'recovery_hash': recoveryHash,
        'created_at': now,
        'updated_at': now,
      });
    });
    return recoveryCode;
  }

  // ---- القفل المؤقت بعد محاولات خاطئة ----

  Future<Duration?> _remainingLock(DatabaseExecutor ex) async {
    final raw = await SettingsStore.readValue(ex, _kLockedUntil);
    if (raw == null) return null;
    final until = DateTime.tryParse(raw);
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  Future<LoginOutcome> _registerFailure() async {
    var failures = 0;
    Duration? lock;
    await _db.write((txn) async {
      failures =
          (int.tryParse(await SettingsStore.readValue(txn, _kFailedCount) ?? '') ??
                  0) +
              1;
      await SettingsStore.writeValue(txn, _kFailedCount, failures.toString());
      if (failures >= _freeAttempts) {
        final exponent = failures - _freeAttempts;
        final minutes = exponent >= 4 ? 15 : (1 << exponent); // 1,2,4,8,15
        lock = Duration(minutes: minutes);
        await SettingsStore.writeValue(
          txn,
          _kLockedUntil,
          dbTime(DateTime.now().add(lock!)),
        );
      }
    });
    return LoginOutcome(
      success: false,
      lockedFor: lock,
      attemptsLeft: failures >= _freeAttempts ? 0 : _freeAttempts - failures,
    );
  }

  /// يصفّر عدّاد المحاولات الفاشلة. لا يكتب شيئًا في القاعدة إن لم يكن هناك
  /// ما يُصفَّر (الحالة المعتادة عند كل دخول ناجح)، فلا معاملة كتابة ولا إعادة
  /// تحميل لكل الشاشات الحيّة بلا داعٍ.
  Future<void> _clearFailures() async {
    final failed = await SettingsStore.readValue(_db.raw, _kFailedCount);
    final locked = await SettingsStore.readValue(_db.raw, _kLockedUntil);
    if (failed == null && locked == null) return;
    await _db.write((txn) async {
      await SettingsStore.deleteValue(txn, _kFailedCount);
      await SettingsStore.deleteValue(txn, _kLockedUntil);
    });
  }

  @override
  Future<LoginOutcome> login({
    required String username,
    required String password,
  }) =>
      _exclusive(() => _login(username: username, password: password));

  Future<LoginOutcome> _login({
    required String username,
    required String password,
  }) async {
    final lock = await _remainingLock(_db.raw);
    if (lock != null) return LoginOutcome(success: false, lockedFor: lock);

    final account = await _account(_db.raw);
    if (account == null) {
      throw const AuthException('لم يتم إعداد حساب المدير بعد');
    }

    final usernameOk = (account['username'] as String).toLowerCase() ==
        username.trim().toLowerCase();
    // نتحقق من كلمة السر دائمًا (حتى لو الاسم خاطئ) لتوحيد زمن الاستجابة.
    final storedHash = account['password_hash'] as String;
    final check = await PasswordHasher.verifyAndCheck(password, storedHash);

    if (usernameOk && check.valid) {
      await _clearFailures();
      if (check.needsRehash) {
        // ترقية صامتة لمرة واحدة: تجزئة قديمة أضعف → تجزئة بالمستوى الحالي.
        // لا تؤخّر الدخول ولا تؤثر على نتيجته إن فشلت.
        unawaited(_upgradePasswordHash(password, storedHash));
      }
      return const LoginOutcome(success: true);
    }
    return _registerFailure();
  }

  Future<void> _upgradePasswordHash(String password, String oldHash) async {
    try {
      final newHash = await PasswordHasher.hash(password);
      if (!_db.isOpen) return;
      await _db.write((txn) async {
        // الشرط يضمن ألا نكتب فوق كلمة سر غُيّرت في هذه الأثناء.
        await txn.update(
          'manager_account',
          {
            'password_hash': newHash,
            'updated_at': dbTime(DateTime.now()),
          },
          where: 'password_hash = ?',
          whereArgs: [oldHash],
        );
      });
    } catch (_) {
      // الترقية تحسين اختياري؛ التجزئة القديمة تبقى صالحة وآمنة.
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _exclusive(() => _changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ));

  Future<void> _changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final lock = await _remainingLock(_db.raw);
    if (lock != null) {
      throw AuthException('محاولات كثيرة. حاول بعد ${_describe(lock)}');
    }
    final passwordError = validatePassword(newPassword);
    if (passwordError != null) throw AuthException(passwordError);

    final account = await _account(_db.raw);
    if (account == null) throw const AuthException('لا يوجد حساب مدير');

    final ok = await PasswordHasher.verify(
      currentPassword,
      account['password_hash'] as String,
    );
    if (!ok) {
      await _registerFailure();
      throw const AuthException('كلمة السر الحالية غير صحيحة');
    }
    final newHash = await PasswordHasher.hash(newPassword);
    await _db.write((txn) async {
      await txn.update('manager_account', {
        'password_hash': newHash,
        'updated_at': dbTime(DateTime.now()),
      });
    });
    await _clearFailures();
  }

  @override
  Future<String> resetWithRecoveryCode({
    required String recoveryCode,
    required String newPassword,
  }) =>
      _exclusive(() => _resetWithRecoveryCode(
            recoveryCode: recoveryCode,
            newPassword: newPassword,
          ));

  Future<String> _resetWithRecoveryCode({
    required String recoveryCode,
    required String newPassword,
  }) async {
    final lock = await _remainingLock(_db.raw);
    if (lock != null) {
      throw AuthException('محاولات كثيرة. حاول بعد ${_describe(lock)}');
    }
    final passwordError = validatePassword(newPassword);
    if (passwordError != null) throw AuthException(passwordError);

    final account = await _account(_db.raw);
    if (account == null) throw const AuthException('لا يوجد حساب مدير');

    final ok = await PasswordHasher.verify(
      normalizeRecoveryCode(recoveryCode),
      account['recovery_hash'] as String,
    );
    if (!ok) {
      await _registerFailure();
      throw const AuthException('رمز الاسترداد غير صحيح');
    }

    final newCode = generateRecoveryCode();
    final hashes = await Future.wait<String>([
      PasswordHasher.hash(newPassword),
      PasswordHasher.hash(normalizeRecoveryCode(newCode)),
    ]);
    await _db.write((txn) async {
      await txn.update('manager_account', {
        'password_hash': hashes[0],
        'recovery_hash': hashes[1],
        'updated_at': dbTime(DateTime.now()),
      });
    });
    await _clearFailures();
    return newCode;
  }

  static String _describe(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes} دقيقة';
    return '${d.inSeconds.clamp(1, 59)} ثانية';
  }
}
