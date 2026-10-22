import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/work_day.dart';
import '../../domain/repositories/work_day_repository.dart';

class WorkDayState {
  final WorkDay? currentDay;
  final bool isRollingOver;
  const WorkDayState({this.currentDay, this.isRollingOver = false});

  WorkDayState copyWith({WorkDay? currentDay, bool? isRollingOver}) =>
      WorkDayState(
        currentDay: currentDay ?? this.currentDay,
        isRollingOver: isRollingOver ?? this.isRollingOver,
      );
}

class WorkDayCubit extends Cubit<WorkDayState> {
  final WorkDayRepository _repository;
  StreamSubscription<WorkDay>? _subscription;

  WorkDayCubit(this._repository) : super(const WorkDayState()) {
    _subscription = _repository.watchCurrentDay().listen(
          (day) => emit(state.copyWith(currentDay: day)),
        );
  }

  Stream<List<WorkDaySummary>> watchSummaries() => _repository.watchSummaries();

  /// يرمي [OpenInvoicesException] إن بقيت فواتير مفتوحة.
  Future<WorkDay> startNewDay() async {
    emit(state.copyWith(isRollingOver: true));
    try {
      return await _repository.startNewDay();
    } finally {
      if (!isClosed) emit(state.copyWith(isRollingOver: false));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
