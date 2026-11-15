import 'package:flutter/material.dart';

import '../../../../core/domain/value_objects/money.dart';

/// أنواع مصاريف الصالة. مشتريات البوفيه ليست منها: تُحسب من فواتير المشتريات
/// (حتى لا تُدخل مرتين).
enum ExpenseKind { maintenance, salaries, supplies, withdrawals, reserve }

extension ExpenseKindX on ExpenseKind {
  String get label {
    switch (this) {
      case ExpenseKind.maintenance:
        return 'صيانة';
      case ExpenseKind.salaries:
        return 'رواتب';
      case ExpenseKind.supplies:
        return 'مستلزمات صالة';
      case ExpenseKind.withdrawals:
        return 'مسحوبات';
      case ExpenseKind.reserve:
        return 'احتياطي';
    }
  }

  IconData get icon {
    switch (this) {
      case ExpenseKind.maintenance:
        return Icons.build_rounded;
      case ExpenseKind.salaries:
        return Icons.badge_rounded;
      case ExpenseKind.supplies:
        return Icons.shopping_basket_rounded;
      case ExpenseKind.withdrawals:
        return Icons.south_west_rounded;
      case ExpenseKind.reserve:
        return Icons.savings_rounded;
    }
  }

  /// المسحوبات يجب أن يُسجَّل معها اسم الشخص الذي سحب.
  bool get needsWithdrawer => this == ExpenseKind.withdrawals;

  /// الوصف إلزامي لكل الأنواع ما عدا المسحوبات (يكفي اسم الساحب) والاحتياطي.
  bool get descriptionRequired =>
      this != ExpenseKind.withdrawals && this != ExpenseKind.reserve;
}

ExpenseKind expenseKindFromName(String name) => ExpenseKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => ExpenseKind.supplies,
    );

/// مصروف مسجَّل (غير محذوف).
class Expense {
  final int id;
  final ExpenseKind kind;
  final Money amount;
  final String description;

  /// يوم المصروف (الوقت دائمًا 00:00).
  final DateTime date;

  /// اسم الشخص الذي سحب (للمسحوبات فقط).
  final String? withdrawer;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Expense({
    required this.id,
    required this.kind,
    required this.amount,
    required this.description,
    required this.date,
    required this.withdrawer,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is Expense &&
      other.id == id &&
      other.kind == kind &&
      other.amount == amount &&
      other.description == description &&
      other.date == date &&
      other.withdrawer == withdrawer &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, kind, amount, description, date, withdrawer, updatedAt);
}

/// ما يدخله المدير عند إضافة مصروف أو تعديله.
class ExpenseInput {
  final ExpenseKind kind;
  final Money amount;
  final String description;
  final DateTime date;
  final String? withdrawer;

  const ExpenseInput({
    required this.kind,
    required this.amount,
    required this.description,
    required this.date,
    this.withdrawer,
  });

  /// يتحقق من المدخلات دون رمي أي استثناء. يعيد رسالة الخطأ العربية، أو null
  /// إن كانت صالحة. ([now] للاختبار فقط.)
  String? validate({DateTime? now}) {
    if (amount.amount <= 0) return ExpenseErrors.amount;
    if (kind.descriptionRequired && description.trim().isEmpty) {
      return ExpenseErrors.description;
    }
    if (kind.needsWithdrawer && (withdrawer?.trim().isEmpty ?? true)) {
      return ExpenseErrors.withdrawer;
    }
    final today = now ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    if (day.isAfter(DateTime(today.year, today.month, today.day))) {
      return ExpenseErrors.futureDate;
    }
    return null;
  }

  /// نسخة منظّفة: وصف وساحب بلا فراغات زائدة، والتاريخ بلا وقت، واسم الساحب
  /// يُحفظ للمسحوبات فقط.
  ExpenseInput sanitized() => ExpenseInput(
        kind: kind,
        amount: amount,
        description: description.trim(),
        date: DateTime(date.year, date.month, date.day),
        withdrawer: kind.needsWithdrawer ? withdrawer?.trim() : null,
      );
}

/// رسائل أخطاء المصاريف (مصدر واحد للواجهة والمستودع).
class ExpenseErrors {
  ExpenseErrors._();

  static const amount = 'المبلغ يجب أن يكون أكبر من صفر';
  static const description = 'اكتب وصف المصروف';
  static const withdrawer = 'اكتب اسم الشخص الذي سحب المبلغ';
  static const futureDate = 'لا يمكن تسجيل مصروف بتاريخ في المستقبل';
  static const notFound = 'هذا المصروف غير موجود أو محذوف';
}

enum ExpenseLogAction { added, edited, deleted }

extension ExpenseLogActionX on ExpenseLogAction {
  /// القيمة المخزَّنة في قاعدة البيانات.
  String get dbName {
    switch (this) {
      case ExpenseLogAction.added:
        return 'add';
      case ExpenseLogAction.edited:
        return 'edit';
      case ExpenseLogAction.deleted:
        return 'delete';
    }
  }

  String get label {
    switch (this) {
      case ExpenseLogAction.added:
        return 'إضافة';
      case ExpenseLogAction.edited:
        return 'تعديل';
      case ExpenseLogAction.deleted:
        return 'حذف';
    }
  }
}

ExpenseLogAction expenseLogActionFromName(String name) =>
    ExpenseLogAction.values.firstWhere(
      (a) => a.dbName == name,
      orElse: () => ExpenseLogAction.edited,
    );

/// سطر في سجل التعديلات: من فعل ماذا ومتى، مع القيم قبل وبعد.
///
/// [before] و[after] لقطتان بالمفاتيح: kind, amount, description, date,
/// withdrawer. الإضافة بلا before، والحذف بلا after.
class ExpenseLogEntry {
  final int id;
  final int expenseId;
  final ExpenseLogAction action;
  final String actor;
  final DateTime at;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;

  const ExpenseLogEntry({
    required this.id,
    required this.expenseId,
    required this.action,
    required this.actor,
    required this.at,
    required this.before,
    required this.after,
  });

  /// أحدث لقطة للمصروف (بعد التعديل، أو قبل الحذف).
  Map<String, Object?> get snapshot => after ?? before ?? const {};

  @override
  bool operator ==(Object other) => other is ExpenseLogEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
