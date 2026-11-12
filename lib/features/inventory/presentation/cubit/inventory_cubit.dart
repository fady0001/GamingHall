import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/utils/time_format.dart';
import '../../../menu/domain/entities/menu_category.dart';
import '../../domain/entities/inventory_models.dart';
import '../../domain/repositories/inventory_repository.dart';

class InventoryState {
  final List<StockRow> rows;
  final List<PurchaseInvoice> invoices;
  final List<StockAdjustment> adjustments;

  /// جرد اليوم المحفوظ (للتاريخ [countDate]).
  final List<CountRecord> todayCounts;
  final String countDate;
  final bool isLoading;

  const InventoryState({
    this.rows = const [],
    this.invoices = const [],
    this.adjustments = const [],
    this.todayCounts = const [],
    this.countDate = '',
    this.isLoading = true,
  });

  List<StockRow> get tracked => rows.where((r) => r.trackStock).toList();
  List<StockRow> get attention => rows.where((r) => r.needsAttention).toList();

  Money get totalValue =>
      sumMoney(rows.where((r) => r.trackStock).map((r) => r.stockValue));

  /// عدد فواتير المشتريات المسجّلة بتاريخ اليوم.
  int get invoicesTodayCount {
    final today = formatDate(DateTime.now());
    return invoices.where((i) => formatDate(i.purchasedAt) == today).length;
  }

  /// مجموع المتبقي (غير المدفوع) على كل الفواتير.
  Money get totalRemaining => sumMoney(invoices
      .map((i) => i.remaining.amount > 0 ? i.remaining : Money.zero));

  CountRecord? countFor(int itemId) {
    for (final c in todayCounts) {
      if (c.itemId == itemId) return c;
    }
    return null;
  }

  InventoryState copyWith({
    List<StockRow>? rows,
    List<PurchaseInvoice>? invoices,
    List<StockAdjustment>? adjustments,
    List<CountRecord>? todayCounts,
    String? countDate,
    bool? isLoading,
  }) =>
      InventoryState(
        rows: rows ?? this.rows,
        invoices: invoices ?? this.invoices,
        adjustments: adjustments ?? this.adjustments,
        todayCounts: todayCounts ?? this.todayCounts,
        countDate: countDate ?? this.countDate,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// المخزون والمشتريات والجرد اليومي. كلها من صلاحيات المدير فقط، ونتحقق هنا
/// (لا في الواجهة فقط) حتى لا يتجاوز الموظف القيد من أي شاشة أخرى.
class InventoryCubit extends Cubit<InventoryState> {
  final InventoryRepository _repository;
  final bool Function() _isManager;
  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<List<CountRecord>>? _countsSub;
  String _countDate;

  InventoryCubit(this._repository, {bool Function()? isManager})
      : _isManager = isManager ?? (() => true),
        _countDate = formatDate(DateTime.now()),
        super(InventoryState(countDate: formatDate(DateTime.now()))) {
    // نتجاهل أي تحميل لم تتغيّر نتيجته: القاعدة تُرسل إشعارًا عند أي كتابة في
    // التطبيق كله، ولا نريد إعادة بناء قوائم المخزون الطويلة بلا داعٍ.
    _subs.add(_repository.watchStock().listen((rows) {
      if (!state.isLoading && listEquals(rows, state.rows)) return;
      emit(state.copyWith(rows: rows, isLoading: false));
    }));
    _subs.add(_repository.watchPurchaseInvoices().listen((list) {
      if (listEquals(list, state.invoices)) return;
      emit(state.copyWith(invoices: list));
    }));
    _subs.add(_repository.watchAdjustments().listen((list) {
      if (listEquals(list, state.adjustments)) return;
      emit(state.copyWith(adjustments: list));
    }));
    _watchCounts(_countDate);
  }

  void _watchCounts(String date) {
    _countsSub?.cancel();
    _countsSub = _repository.watchCounts(date).listen((list) {
      if (date == state.countDate && listEquals(list, state.todayCounts)) return;
      emit(state.copyWith(todayCounts: list, countDate: date));
    });
  }

  /// يتأكد أن تاريخ الجرد المعروض هو تاريخ اليوم (إن بقي التطبيق مفتوحًا
  /// بعد منتصف الليل). تُستدعى عند فتح تبويب الجرد.
  void refreshCountDate() {
    final today = formatDate(DateTime.now());
    if (today == _countDate) return;
    _countDate = today;
    _watchCounts(today);
  }

  void _requireManager() {
    if (!_isManager()) {
      throw StateError('المخزون والجرد من صلاحيات المدير فقط');
    }
  }

  Future<int> saveInvoice(PurchaseInvoiceInput input) {
    _requireManager();
    return _repository.saveInvoice(input);
  }

  Future<void> deleteInvoice(int id) {
    _requireManager();
    return _repository.deleteInvoice(id);
  }

  Future<void> addPayment({
    required int invoiceId,
    required Money amount,
    DateTime? paidAt,
    String? note,
  }) {
    _requireManager();
    return _repository.addPayment(
        invoiceId: invoiceId, amount: amount, paidAt: paidAt, note: note);
  }

  Future<void> deletePayment(int id) {
    _requireManager();
    return _repository.deletePayment(id);
  }

  Future<void> adjustStock({
    required int itemId,
    required StockAdjustMode mode,
    required int quantity,
    required String reason,
  }) {
    _requireManager();
    return _repository.adjustStock(
        itemId: itemId, mode: mode, quantity: quantity, reason: reason);
  }

  Future<int> createStockItem({
    required String name,
    required MenuCategory category,
  }) {
    _requireManager();
    return _repository.createStockItem(name: name, category: category);
  }

  Future<void> updateStockSettings({
    required int itemId,
    required bool trackStock,
    required int minStock,
    required bool isSellable,
    Money? price,
  }) {
    _requireManager();
    return _repository.updateStockSettings(
      itemId: itemId,
      trackStock: trackStock,
      minStock: minStock,
      isSellable: isSellable,
      price: price,
    );
  }

  Future<int> saveCounts(List<CountEntry> entries) {
    _requireManager();
    return _repository.saveCounts(_countDate, entries);
  }

  @override
  Future<void> close() {
    for (final s in _subs) {
      s.cancel();
    }
    _countsSub?.cancel();
    return super.close();
  }
}
