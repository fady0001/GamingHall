import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/domain/value_objects/money.dart';
import '../../../menu/domain/entities/menu_category.dart';

/// صنف مع كميته الحالية في المخزون.
///
/// الكمية الحالية = (مجموع حركات المخزون: مشتريات + تسويات الجرد + التعديل
/// اليدوي) − (ما بيع بعد بدء تتبّع الصنف). "بدء التتبّع" يحدث عند أول شراء أو
/// أول جرد أو أول تعديل للصنف، فلا تُخصم المبيعات القديمة.
class StockRow {
  final int itemId;
  final String name;
  final MenuCategory category;

  /// هل يُتتبَّع مخزون هذا الصنف؟ (الخدمات كالأركيلة والثلج يمكن استثناؤها).
  final bool trackStock;

  /// هل يُباع للزبائن (يظهر في قائمة المشتريات والفواتير)؟ الأصناف التي
  /// تُضاف من شاشة الشراء (كاسات، مناديل...) لا تُباع.
  final bool isSellable;

  /// سعر البيع (0 للصنف الذي لا يُباع).
  final Money price;

  /// حد التنبيه: إن نزلت الكمية إلى هذا الرقم أو أقل يظهر تحذير (لا يمنع البيع).
  final int minStock;

  /// تكلفة القطعة الواحدة عند آخر شراء.
  final Money unitCost;

  /// false = لم يُسجَّل لهذا الصنف شراء ولا جرد بعد.
  final bool started;

  /// قد تكون سالبة إن بيع أكثر مما سُجّل (يُصحَّح بالجرد).
  final int onHand;

  const StockRow({
    required this.itemId,
    required this.name,
    required this.category,
    required this.trackStock,
    required this.isSellable,
    required this.price,
    required this.minStock,
    required this.unitCost,
    required this.started,
    required this.onHand,
  });

  bool get isOut => trackStock && started && onHand <= 0;
  bool get isLow => trackStock && started && onHand > 0 && onHand <= minStock;
  bool get needsAttention => isOut || isLow;

  /// قيمة ما في المخزون بسعر التكلفة (لا تُحسب الكميات السالبة).
  Money get stockValue => Money(onHand > 0 ? unitCost.amount * onHand : 0);

  @override
  bool operator ==(Object other) =>
      other is StockRow && other.itemId == itemId && other.name == name && other.category == category && other.trackStock == trackStock && other.isSellable == isSellable && other.price == price && other.minStock == minStock && other.unitCost == unitCost && other.started == started && other.onHand == onHand;

  @override
  int get hashCode => Object.hash(itemId, name, category, trackStock, isSellable, price, minStock, unitCost, started, onHand);
}

/// تكلفة القطعة من سعر الطرد (تقريب لأقرب ليرة بحساب صحيح فقط).
int unitCostFor(int packPrice, int piecesPerPack) {
  if (piecesPerPack <= 0) return 0;
  return (packPrice + piecesPerPack ~/ 2) ~/ piecesPerPack;
}

// ───────────────────────── المشتريات (فواتير) ─────────────────────────

/// طريقة إدخال سطر الشراء.
enum PurchaseMode {
  /// عدد طرود × قطع بالطرد × سعر الطرد.
  pack,

  /// عدد قطع × سعر القطعة الواحدة.
  pieceUnitPrice,

  /// عدد قطع + السعر الإجمالي (سعر القطعة = الإجمالي ÷ العدد).
  pieceTotalPrice,
}

/// نتيجة حساب سطر شراء.
class PurchaseLineCalc {
  /// "pack" أو "piece" (كما يُخزَّن).
  final String entryMode;

  /// في الشراء بالقطعة: packs = عدد القطع و piecesPerPack = 1.
  final int packs;
  final int piecesPerPack;
  final Money packPrice;
  final int totalPieces;
  final Money unitCost;
  final Money totalCost;

  const PurchaseLineCalc({
    required this.entryMode,
    required this.packs,
    required this.piecesPerPack,
    required this.packPrice,
    required this.totalPieces,
    required this.unitCost,
    required this.totalCost,
  });
}

/// سطر شراء كما يدخله المدير (قبل الحفظ).
class PurchaseLineInput {
  final int itemId;
  final PurchaseMode mode;

  /// عدد الطرود (pack) أو عدد القطع (الوضعان الآخران).
  final int quantity;

  /// قطع الطرد (للوضع pack فقط).
  final int? piecesPerPack;

  /// سعر الطرد (pack) أو سعر القطعة (pieceUnitPrice) أو الإجمالي (pieceTotalPrice).
  final Money price;

  const PurchaseLineInput({
    required this.itemId,
    required this.mode,
    required this.quantity,
    this.piecesPerPack,
    required this.price,
  });

  PurchaseLineCalc calc() {
    if (quantity <= 0) {
      throw ArgumentError(mode == PurchaseMode.pack
          ? 'عدد الطرود يجب أن يكون أكبر من صفر'
          : 'عدد القطع يجب أن يكون أكبر من صفر');
    }
    if (quantity > 100000) throw ArgumentError('الرقم كبير جدًا');
    if (price.amount <= 0) throw ArgumentError('أدخل السعر');

    switch (mode) {
      case PurchaseMode.pack:
        final per = piecesPerPack ?? 0;
        if (per <= 0) {
          throw ArgumentError('عدد القطع في الطرد يجب أن يكون أكبر من صفر');
        }
        if (per > 100000) throw ArgumentError('الرقم كبير جدًا');
        return PurchaseLineCalc(
          entryMode: 'pack',
          packs: quantity,
          piecesPerPack: per,
          packPrice: price,
          totalPieces: quantity * per,
          unitCost: Money(unitCostFor(price.amount, per)),
          totalCost: Money(quantity * price.amount),
        );
      case PurchaseMode.pieceUnitPrice:
        return PurchaseLineCalc(
          entryMode: 'piece',
          packs: quantity,
          piecesPerPack: 1,
          packPrice: price,
          totalPieces: quantity,
          unitCost: price,
          totalCost: Money(quantity * price.amount),
        );
      case PurchaseMode.pieceTotalPrice:
        final unit = unitCostFor(price.amount, quantity);
        return PurchaseLineCalc(
          entryMode: 'piece',
          packs: quantity,
          piecesPerPack: 1,
          packPrice: Money(unit),
          totalPieces: quantity,
          unitCost: Money(unit),
          totalCost: price,
        );
    }
  }
}

/// سطر محفوظ في فاتورة مشتريات.
class PurchaseLine {
  final int id;
  final int itemId;
  final String itemName;
  final String entryMode; // pack | piece
  final int packs;
  final int piecesPerPack;
  final Money packPrice;
  final int totalPieces;
  final Money unitCost;
  final Money totalCost;

  const PurchaseLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.entryMode,
    required this.packs,
    required this.piecesPerPack,
    required this.packPrice,
    required this.totalPieces,
    required this.unitCost,
    required this.totalCost,
  });

  bool get isPack => entryMode == 'pack';

  /// نص مختصر لكمية السطر.
  String get quantityText =>
      isPack ? '$packs طرد × $piecesPerPack قطعة = $totalPieces قطعة' : '$totalPieces قطعة';

  /// يعيد السطر لصيغة الإدخال (لتعديل الفاتورة).
  PurchaseLineInput toInput() => isPack
      ? PurchaseLineInput(
          itemId: itemId,
          mode: PurchaseMode.pack,
          quantity: packs,
          piecesPerPack: piecesPerPack,
          price: packPrice,
        )
      : PurchaseLineInput(
          itemId: itemId,
          mode: PurchaseMode.pieceTotalPrice,
          quantity: totalPieces,
          price: totalCost,
        );

  @override
  bool operator ==(Object other) =>
      other is PurchaseLine && other.id == id && other.itemId == itemId && other.itemName == itemName && other.entryMode == entryMode && other.packs == packs && other.piecesPerPack == piecesPerPack && other.packPrice == packPrice && other.totalPieces == totalPieces && other.unitCost == unitCost && other.totalCost == totalCost;

  @override
  int get hashCode => Object.hash(id, itemId, itemName, entryMode, packs, piecesPerPack, packPrice, totalPieces, unitCost, totalCost);
}

class PurchasePayment {
  final int id;
  final int invoiceId;
  final Money amount;
  final DateTime paidAt;
  final String? note;

  const PurchasePayment({
    required this.id,
    required this.invoiceId,
    required this.amount,
    required this.paidAt,
    this.note,
  });

  @override
  bool operator ==(Object other) =>
      other is PurchasePayment && other.id == id && other.invoiceId == invoiceId && other.amount == amount && other.paidAt == paidAt && other.note == note;

  @override
  int get hashCode => Object.hash(id, invoiceId, amount, paidAt, note);
}

enum PaymentStatus { paid, partial, unpaid }

/// فاتورة مشتريات (عدة أصناف) مع دفعاتها.
class PurchaseInvoice {
  final int id;
  final DateTime purchasedAt;
  final String? supplier;
  final String? invoiceNo;
  final String? note;
  final Money discount;
  final List<PurchaseLine> lines;
  final List<PurchasePayment> payments;

  const PurchaseInvoice({
    required this.id,
    required this.purchasedAt,
    this.supplier,
    this.invoiceNo,
    this.note,
    this.discount = Money.zero,
    this.lines = const [],
    this.payments = const [],
  });

  Money get itemsTotal => sumMoney(lines.map((l) => l.totalCost));

  /// المطلوب دفعه = مجموع الأسطر − الخصم.
  Money get payable => itemsTotal - discount;
  Money get paid => sumMoney(payments.map((p) => p.amount));
  Money get remaining => payable - paid;

  PaymentStatus get status {
    if (remaining.amount <= 0) return PaymentStatus.paid;
    if (paid.amount <= 0) return PaymentStatus.unpaid;
    return PaymentStatus.partial;
  }

  @override
  bool operator ==(Object other) =>
      other is PurchaseInvoice && other.id == id && other.purchasedAt == purchasedAt && other.supplier == supplier && other.invoiceNo == invoiceNo && other.note == note && other.discount == discount && listEquals(other.lines, lines) && listEquals(other.payments, payments);

  @override
  int get hashCode => Object.hash(id, purchasedAt, supplier, invoiceNo, note, discount, lines, payments);
}

/// ما يرسله المدير لإنشاء/تعديل فاتورة.
class PurchaseInvoiceInput {
  /// null = فاتورة جديدة.
  final int? id;
  final DateTime purchasedAt;
  final String? supplier;
  final String? invoiceNo;
  final String? note;
  final Money discount;
  final List<PurchaseLineInput> lines;

  /// المدفوع عند الإنشاء فقط (الدفعات بعدها من "تسديد دفعة").
  final Money initialPaid;

  const PurchaseInvoiceInput({
    this.id,
    required this.purchasedAt,
    this.supplier,
    this.invoiceNo,
    this.note,
    this.discount = Money.zero,
    required this.lines,
    this.initialPaid = Money.zero,
  });
}

// ───────────────────────── التعديل اليدوي ─────────────────────────

enum StockAdjustMode {
  /// زيادة بعدد.
  increase,

  /// نقص بعدد.
  decrease,

  /// ضبط الكمية على رقم محدد.
  setTo,
}

class StockAdjustment {
  final int id;
  final int itemId;
  final String itemName;

  /// موجب = زيادة، سالب = نقص.
  final int qty;
  final String reason;
  final DateTime createdAt;

  const StockAdjustment({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.reason,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      other is StockAdjustment && other.id == id && other.itemId == itemId && other.itemName == itemName && other.qty == qty && other.reason == reason && other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, itemId, itemName, qty, reason, createdAt);
}

// ───────────────────────── الجرد ─────────────────────────

/// رقم يدخله المدير في الجرد لصنف واحد.
class CountEntry {
  final int itemId;
  final int counted;
  const CountEntry(this.itemId, this.counted);
}

/// نتيجة جرد صنف في يوم معيّن.
class CountRecord {
  final int id;
  final int itemId;
  final String itemName;
  final String date; // yyyy-MM-dd
  final int expected;
  final int counted;
  final DateTime countedAt;

  const CountRecord({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.date,
    required this.expected,
    required this.counted,
    required this.countedAt,
  });

  /// الفرق = الفعلي − المتوقع. سالب = نقص، موجب = زيادة.
  int get difference => counted - expected;

  @override
  bool operator ==(Object other) =>
      other is CountRecord && other.id == id && other.itemId == itemId && other.itemName == itemName && other.date == date && other.expected == expected && other.counted == counted && other.countedAt == countedAt;

  @override
  int get hashCode => Object.hash(id, itemId, itemName, date, expected, counted, countedAt);
}
