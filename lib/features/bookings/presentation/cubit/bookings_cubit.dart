import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/booking.dart';
import '../../domain/repositories/booking_repository.dart';

class BookingsState {
  final List<Booking> bookings;
  final bool isLoading;
  const BookingsState({this.bookings = const [], this.isLoading = true});
}

class BookingsCubit extends Cubit<BookingsState> {
  final BookingRepository _repository;
  StreamSubscription<List<Booking>>? _subscription;

  BookingsCubit(this._repository) : super(const BookingsState()) {
    _subscription = _repository.watchAll().listen(
          (list) => emit(BookingsState(bookings: list, isLoading: false)),
        );
  }

  Future<Booking> create({
    required String customerName,
    required String phone,
    required int resourceId,
    required int playerCount,
    required DateTime startAt,
    required DateTime endAt,
    bool isOpen = false,
  }) =>
      _repository.create(
        customerName: customerName,
        phone: phone,
        resourceId: resourceId,
        playerCount: playerCount,
        startAt: startAt,
        endAt: endAt,
        isOpen: isOpen,
      );

  Future<void> cancel(int id) => _repository.cancel(id);

  Future<int> convertToInvoice(int id) => _repository.convertToInvoice(id);

  Future<void> markReminderShown(int id) => _repository.markReminderShown(id);

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
