import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/report.dart';
import '../../domain/repositories/report_repository.dart';
import '../../domain/resolve_range.dart';

class ReportsState {
  final RangePreset preset;
  final DateRange? custom;
  final Report? report;
  final bool isLoading;
  final String? error;

  const ReportsState({
    this.preset = RangePreset.today,
    this.custom,
    this.report,
    this.isLoading = true,
    this.error,
  });
}

class ReportsCubit extends Cubit<ReportsState> {
  final ReportRepository _repository;
  final DateTime Function() _currentDayStart;
  int _request = 0;

  ReportsCubit(this._repository, this._currentDayStart)
      : super(const ReportsState());

  Future<void> load({RangePreset? preset, DateRange? custom}) async {
    final p = preset ?? state.preset;
    final c = custom ?? (p == RangePreset.custom ? state.custom : null);
    emit(ReportsState(
      preset: p,
      custom: c,
      report: state.report,
      isLoading: true,
    ));
    final mine = ++_request;
    try {
      final range = resolveRange(
        p,
        now: DateTime.now(),
        currentDayStart: _currentDayStart(),
        custom: c,
      );
      final report = await _repository.build(range);
      if (mine != _request || isClosed) return;
      emit(ReportsState(preset: p, custom: c, report: report, isLoading: false));
    } catch (e) {
      if (mine != _request || isClosed) return;
      emit(ReportsState(
        preset: p,
        custom: c,
        report: state.report,
        isLoading: false,
        error: 'تعذّر تحميل التقرير: $e',
      ));
    }
  }
}
