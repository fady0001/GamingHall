
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/security/manager_marker.dart';
import '../../domain/entities/app_role.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthState {
  /// null = لم يُعرف بعد هل أُعدّ حساب المدير (شاشة تحميل قصيرة).
  final bool? hasManagerAccount;
  final AppRole? role;

  /// تنبيه لمرة واحدة: عاد التطبيق لوضع الموظف بسبب عدم النشاط.
  final bool autoLoggedOutNotice;

  /// كان لهذا الجهاز حساب مدير لكنه اختفى (قاعدة البيانات محذوفة أو بديلة).
  final bool accountMissing;

  const AuthState({
    this.hasManagerAccount,
    this.role,
    this.autoLoggedOutNotice = false,
    this.accountMissing = false,
  });

  bool get isManager => role == AppRole.manager;
  bool get isEmployee => role == AppRole.employee;
  bool get roleSelected => role != null;

  AuthState copyWith({
    bool? hasManagerAccount,
    Object? role = _keep,
    bool? autoLoggedOutNotice,
    bool? accountMissing,
  }) {
    return AuthState(
      hasManagerAccount: hasManagerAccount ?? this.hasManagerAccount,
      role: identical(role, _keep) ? this.role : role as AppRole?,
      autoLoggedOutNotice: autoLoggedOutNotice ?? this.autoLoggedOutNotice,
      accountMissing: accountMissing ?? this.accountMissing,
    );
  }

  static const Object _keep = Object();
}

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repository;

  AuthCubit(this._repository) : super(const AuthState()) {
    _loadSetup();
  }

  Future<void> _loadSetup() async {
    final has = await _repository.hasManagerAccount();
    if (has) {
      // يغطي التثبيتات التي أُنشئ حسابها قبل وجود العلامة.
      await ManagerMarker.write();
      if (!isClosed) emit(state.copyWith(hasManagerAccount: true));
      return;
    }
    final missing = await ManagerMarker.exists();
    if (!isClosed) {
      emit(state.copyWith(hasManagerAccount: false, accountMissing: missing));
    }
  }

  /// لا يوجد خروج تلقائي من وضع المدير (بقرار المالك). تبقى الدالة لأن
  /// بعض الأكواد قد تستدعيها.
  void touch() {}

  void acknowledgeNotice() {
    if (state.autoLoggedOutNotice) emit(state.copyWith(autoLoggedOutNotice: false));
  }

  void continueAsEmployee() {
    emit(state.copyWith(role: AppRole.employee));
  }

  /// الإعداد الأول: ينشئ حساب المدير ويعيد رمز الاسترداد. لا نبدّل الشاشة هنا
  /// حتى يرى المستخدم الرمز أولًا؛ بعدها تُستدعى [finishSetup].
  Future<String> setUpManager({
    required String username,
    required String password,
  }) async {
    if (state.accountMissing) {
      throw StateError('حساب المدير مفقود: استعد نسخة احتياطية أولًا');
    }
    final code = await _repository.createManagerAccount(
      username: username,
      password: password,
    );
    await ManagerMarker.write();
    return code;
  }

  /// يُنهي الإعداد الأول وينتقل التطبيق إلى شاشة اختيار الدور.
  void finishSetup() => emit(state.copyWith(hasManagerAccount: true));

  Future<LoginOutcome> loginAsManager({
    required String username,
    required String password,
  }) async {
    final outcome = await _repository.login(username: username, password: password);
    if (outcome.success) {
      touch();
      emit(state.copyWith(role: AppRole.manager, autoLoggedOutNotice: false));
    }
    return outcome;
  }

  /// بعد استرداد كلمة السر برمز الاسترداد (يعيد رمزًا جديدًا).
  Future<String> resetPassword({
    required String recoveryCode,
    required String newPassword,
  }) =>
      _repository.resetWithRecoveryCode(
        recoveryCode: recoveryCode,
        newPassword: newPassword,
      );

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  Future<String?> managerUsername() => _repository.managerUsername();

  /// الرجوع لشاشة اختيار الدور.
  void logout() => emit(state.copyWith(role: null));

}
