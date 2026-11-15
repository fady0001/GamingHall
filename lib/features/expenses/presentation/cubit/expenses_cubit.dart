import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/validation_exception.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/buffet_payment.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';

class ExpensesState {
  /// الشهر المعروض ([month] من 1 إلى 12).
  final int year;
  final int month;
  final List<Expense> expenses;

  /// دفعات مشتريات البوفيه في الشهر (للعرض فقط، تُحسب مع المصاريف).
  final List<BuffetPayment> buffetPayments;

  /// غير المسدَّد من فواتير المشتريات حتى نهاية الشهر المعروض.
  final Money buffetUnpaid;
  final List<ExpenseLogEntry> log;
  final List<String> withdrawerNames;

  /// true حتى تصل مصاريف الشهر المعروض.
  final bool isLoading;

  const ExpensesState({
    required this.year,
    required this.month,
    this.expenses = const [],
    this.buffetPayments = const [],
    this.buffetUnpaid = Money.zero,
    this.log = const [],
    this.withdrawerNames = const [],
    this.isLoading = true,
  });

  bool get isCurrentMonth {
    final now = DateTime.now();
    return year == now.year && month == now.month;
  }

  /// لا نسمح بالانتقال إلى شهر بعد الشهر الحالي.
  bool get canGoNext => !isCurrentMonth;

  Money totalFor(ExpenseKind kind) => sumMoney(
        expenses.where((e) => e.kind == kind).map((e) => e.amount),
      );

  /// مجموع ما دُفع للمشتريات خلال الشهر.
  Money get buffetTotal => sumMoney(buffetPayments.map((p) => p.amount));

  /// إجمالي الشهر: كل المصاريف + مشتريات البوفيه.
  Money get total =>
      sumMoney(expenses.map((e) => e.amount)) + buffetTotal;

  ExpensesState copyWith({
    int? year,
    int? month,
    List<Expense>? expenses,
    List<BuffetPayment>? buffetPayments,
    Money? buffetUnpaid,
    List<ExpenseLogEntry>? log,
    List<String>? withdrawerNames,
    bool? isLoading,
  }) =>
      ExpensesState(
        year: year ?? this.year,
        month: month ?? this.month,
        expenses: expenses ?? this.expenses,
        buffetPayments: buffetPayments ?? this.buffetPayments,
        buffetUnpaid: buffetUnpaid ?? this.buffetUnpaid,
        log: log ?? this.log,
        withdrawerNames: withdrawerNames ?? this.withdrawerNames,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// مصاريف الصالة. من صلاحيات المدير فقط، ونتحقق هنا (لا في الواجهة فقط) حتى
/// لا يتجاوز الموظف القيد من أي شاشة أخرى.
class ExpensesCubit extends Cubit<ExpensesState> {
  final ExpenseRepository _repository;
  final bool Function() _isManager;
  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<List<Expense>>? _monthSub;
  StreamSubscription<List<BuffetPayment>>? _buffetSub;
  StreamSubscription<Money>? _unpaidSub;
  bool _expensesLoaded = false;
  bool _buffetLoaded = false;

  ExpensesCubit(this._repository, {bool Function()? isManager})
      : _isManager = isManager ?? (() => true),
        super(ExpensesState(
          year: DateTime.now().year,
          month: DateTime.now().month,
        )) {
    _subs.add(_repository.watchLog().listen((list) {
      if (listEquals(list, state.log)) return;
      emit(state.copyWith(log: list));
    }));
    _subs.add(_repository.watchWithdrawerNames().listen((list) {
      if (listEquals(list, state.withdrawerNames)) return;
      emit(state.copyWith(withdrawerNames: list));
    }));
    _watchMonth(state.year, state.month);
  }

  void _watchMonth(int year, int month) {
    _monthSub?.cancel();
    _buffetSub?.cancel();
    _unpaidSub?.cancel();
    _expensesLoaded = false;
    _buffetLoaded = false;
    _monthSub = _repository.watchMonth(year, month).listen((list) {
      // نتجاهل بث شهر سابق وصل متأخرًا.
      if (year != state.year || month != state.month) return;
      if (_expensesLoaded && listEquals(list, state.expenses)) return;
      _expensesLoaded = true;
      emit(state.copyWith(expenses: list, isLoading: !_buffetLoaded));
    });
    _buffetSub = _repository.watchBuffetPayments(year, month).listen((list) {
      if (year != state.year || month != state.month) return;
      if (_buffetLoaded && listEquals(list, state.buffetPayments)) return;
      _buffetLoaded = true;
      emit(state.copyWith(buffetPayments: list, isLoading: !_expensesLoaded));
    });
    _unpaidSub = _repository.watchBuffetUnpaid(year, month).listen((value) {
      if (year != state.year || month != state.month) return;
      if (value == state.buffetUnpaid) return;
      emit(state.copyWith(buffetUnpaid: value));
    });
  }

  void _setMonth(int year, int month) {
    emit(state.copyWith(
      year: year,
      month: month,
      expenses: const [],
      buffetPayments: const [],
      buffetUnpaid: Money.zero,
      isLoading: true,
    ));
    _watchMonth(year, month);
  }

  void previousMonth() {
    final prev = DateTime(state.year, state.month - 1);
    _setMonth(prev.year, prev.month);
  }

  void nextMonth() {
    if (!state.canGoNext) return;
    final next = DateTime(state.year, state.month + 1);
    _setMonth(next.year, next.month);
  }

  void goToCurrentMonth() {
    if (state.isCurrentMonth) return;
    final now = DateTime.now();
    _setMonth(now.year, now.month);
  }

  /// ينفّذ [action] للمدير فقط. الرفض يعود Future فاشلًا (لا `throw`).
  Future<T> _asManager<T>(Future<T> Function() action) {
    if (!_isManager()) {
      return Future<T>.error(
        const ValidationException('المصاريف من صلاحيات المدير فقط'),
      );
    }
    return action();
  }

  Future<int> add(ExpenseInput input) =>
      _asManager(() => _repository.add(input));

  Future<void> update(int id, ExpenseInput input) =>
      _asManager(() => _repository.update(id, input));

  Future<void> delete(int id) => _asManager(() => _repository.delete(id));

  @override
  Future<void> close() {
    for (final s in _subs) {
      s.cancel();
    }
    _monthSub?.cancel();
    _buffetSub?.cancel();
    _unpaidSub?.cancel();
    return super.close();
  }
}
