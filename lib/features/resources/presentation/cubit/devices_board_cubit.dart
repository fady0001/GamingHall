import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bookings/presentation/cubit/bookings_cubit.dart';
import '../../../invoices/presentation/cubit/invoices_cubit.dart';
import '../../domain/entities/resource_status.dart';
import '../../domain/usecases/build_resource_views.dart';
import 'resources_cubit.dart';

class DevicesBoardState {
  final List<ResourceView> views;
  final bool isLoading;
  const DevicesBoardState({this.views = const [], this.isLoading = true});

  int countOf(ResourceStatus s) => views.where((v) => v.status == s).length;
}

/// يجمع الأجهزة + الفواتير المفتوحة + الحجوزات في عرض واحد بحالات حيّة.
/// يُعاد الحساب عند أي تغيّر، وكل 20 ثانية لالتقاط دخول نافذة الحجز.
class DevicesBoardCubit extends Cubit<DevicesBoardState> {
  final ResourcesCubit _resources;
  final InvoicesCubit _invoices;
  final BookingsCubit _bookings;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _timer;

  DevicesBoardCubit(this._resources, this._invoices, this._bookings)
      : super(const DevicesBoardState()) {
    _recompute();
    _subs.addAll([
      _resources.stream.listen((_) => _recompute()),
      _invoices.stream.listen((_) => _recompute()),
      _bookings.stream.listen((_) => _recompute()),
    ]);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _recompute());
  }

  void _recompute() {
    final loading = _resources.state.isLoading ||
        _invoices.state.isLoading ||
        _bookings.state.isLoading;
    emit(DevicesBoardState(
      isLoading: loading,
      views: buildResourceViews(
        resources: _resources.state.resources,
        openInvoices: _invoices.state.open,
        bookings: _bookings.state.bookings,
        now: DateTime.now(),
      ),
    ));
  }

  @override
  Future<void> close() {
    for (final s in _subs) {
      s.cancel();
    }
    _timer?.cancel();
    return super.close();
  }
}
