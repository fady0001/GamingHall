class LoginOutcome {
  final bool success;

  /// إن كان الحساب مقفلًا مؤقتًا بعد محاولات خاطئة كثيرة.
  final Duration? lockedFor;

  final int attemptsLeft;

  const LoginOutcome({
    required this.success,
    this.lockedFor,
    this.attemptsLeft = 0,
  });

  bool get isLocked => lockedFor != null;
}

/// خطأ مصادقة برسالة عربية جاهزة للعرض.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

abstract class AuthRepository {
  Future<bool> hasManagerAccount();

  /// ينشئ حساب المدير (مرة واحدة) ويعيد رمز الاسترداد (يُعرض مرة واحدة فقط).
  Future<String> createManagerAccount({
    required String username,
    required String password,
  });

  Future<LoginOutcome> login({
    required String username,
    required String password,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// استرداد الحساب برمز الاسترداد. يعيد رمز استرداد جديدًا.
  Future<String> resetWithRecoveryCode({
    required String recoveryCode,
    required String newPassword,
  });

  Future<String?> managerUsername();
}

const int kMinPasswordLength = 6;

/// يعيد رسالة خطأ إن كانت كلمة السر غير مقبولة، وإلا null.
String? validatePassword(String password) {
  if (password.trim().length < kMinPasswordLength) {
    return 'كلمة السر يجب ألا تقل عن $kMinPasswordLength أحرف';
  }
  if (password.trim().isEmpty) return 'كلمة السر مطلوبة';
  return null;
}
