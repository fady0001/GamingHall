import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../days/domain/entities/work_day.dart';
import '../../../days/domain/repositories/work_day_repository.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/repositories/invoice_repository.dart';

class InvoicesState {
  /// الفواتير المفتوحة حاليًا (الأحدث أولًا).
  final List<Invoice> open;

  /// كل فواتير يوم العمل الحالي (مفتوحة ومغلقة).
  final List<Invoice> today;

  final bool isLoading;

  const InvoicesState({
    this.open = const [],
    this.today = const [],
    this.isLoading = true,
  });

  Invoice? openById(int id) {
    for (final i in open) {
      if (i.id == id) return i;
    }
    return null;
  }

  List<Invoice> get todayClosed =>
      today.where((i) => !i.isOpen).toList()
        ..sort((a, b) => (b.closedAt ?? b.createdAt).compareTo(a.closedAt ?? a.createdAt));
}

class InvoicesCubit extends Cubit<InvoicesState> {
  final InvoiceRepository _repository;
  final WorkDayRepository _days;
  StreamSubscription<List<Invoice>>? _openSub;
  StreamSubscription<WorkDay>? _daySub;
  StreamSubscription<List<Invoice>>? _todaySub;
  bool _openLoaded = false;

  InvoicesCubit(this._repository, this._days) : super(const InvoicesState()) {
    _openSub = _repository.watchOpen().listen((list) {
      _openLoaded = true;
      emit(InvoicesState(open: list, today: state.today, isLoading: false));
    });
    _daySub = _days.watchCurrentDay().listen((day) {
      _todaySub?.cancel();
      _todaySub = _repository.watchByDay(day.id).listen((list) {
        emit(InvoicesState(open: state.open, today: list, isLoading: !_openLoaded));
      });
    });
  }

  Future<Invoice> create(String customerName) => _repository.create(customerName);

  Future<void> startPlay({
    required int invoiceId,
    required int resourceId,
    required int playerCount,
    int? plannedMinutes,
  }) =>
      _repository.startPlay(
        invoiceId: invoiceId,
        resourceId: resourceId,
        playerCount: playerCount,
        plannedMinutes: plannedMinutes,
      );

  Future<List<PlayLine>> endExpiredFixedLines() => _repository.endExpiredFixedLines();

  Future<void> extendPlay(int playLineId, int extraMinutes) =>
      _repository.extendPlay(playLineId: playLineId, extraMinutes: extraMinutes);

  Future<void> stopPlay(int playLineId) => _repository.stopPlay(playLineId);

  Future<void> addItem({
    required int invoiceId,
    required int menuItemId,
    int quantity = 1,
  }) =>
      _repository.addItem(
        invoiceId: invoiceId,
        menuItemId: menuItemId,
        quantity: quantity,
      );

  Future<void> setItemQuantity(int itemLineId, int quantity) =>
      _repository.setItemQuantity(itemLineId, quantity);

  Future<Invoice> checkout(int invoiceId) => _repository.checkout(invoiceId);

  Future<void> deleteIfEmpty(int invoiceId) => _repository.deleteIfEmpty(invoiceId);

  Future<List<Invoice>> search(InvoiceSearchFilter filter) =>
      _repository.search(filter);

  Future<Invoice?> getById(int id) => _repository.getById(id);

  Stream<Invoice?> watchById(int id) => _repository.watchById(id);

  @override
  Future<void> close() {
    _openSub?.cancel();
    _daySub?.cancel();
    _todaySub?.cancel();
    return super.close();
  }
}
