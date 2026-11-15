import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/validation_exception.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';

class ExpensesState {
  /// الشهر المعروض ([month] من 1 إلى 12).
  final int year;
  final int month;
  final List<Expense> expenses;
  final List<ExpenseLogEntry> log;
  final List<String> withdrawerNames;

  /// true حتى تصل مصاريف الشهر المعروض.
  final bool isLoading;

  const ExpensesState({
    required this.year,
    required this.month,
    this.expenses = const [],
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

  Money get total => sumMoney(expenses.map((e) => e.amount));

  ExpensesState copyWith({
    int? year,
    int? month,
    List<Expense>? expenses,
    List<ExpenseLogEntry>? log,
    List<String>? withdrawerNames,
    bool? isLoading,
  }) =>
      ExpensesState(
        year: year ?? this.year,
        month: month ?? this.month,
        expenses: expenses ?? this.expenses,
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
    _monthSub = _repository.watchMonth(year, month).listen((list) {
      // نتجاهل بث شهر سابق وصل متأخرًا.
      if (year != state.year || month != state.month) return;
      if (!state.isLoading && listEquals(list, state.expenses)) return;
      emit(state.copyWith(expenses: list, isLoading: false));
    });
  }

  void _setMonth(int year, int month) {
    emit(state.copyWith(
      year: year,
      month: month,
      expenses: const [],
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
    return super.close();
  }
}
