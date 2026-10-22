import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextWidthBasis;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../resources/domain/entities/resource_kind.dart';
import '../../../core/constants/app_info.dart';
import '../../../core/domain/value_objects/money.dart';
import '../../../core/utils/number_format.dart';
import '../../../core/utils/time_format.dart';
import '../../invoices/domain/entities/invoice.dart';
import '../../settings/domain/entities/app_settings.dart';

/// يبني فاتورة PDF بعرض إيصال حراري (80mm).
///
/// لماذا صورة؟ مكتبة pdf لا تُشكّل الحروف العربية ولا تُرتّب النص ثنائي
/// الاتجاه (عربي + أرقام + إنجليزي) بشكل موثوق: كانت الحروف تتقطّع وتضيع
/// أحرف (مثل "ل") ويختلّ الترتيب. لذلك نرسم الفاتورة بمحرّك نصوص فلتر نفسه
/// (نفس خط Tajawal ونفس التشكيل الصحيح الذي تراه في التطبيق) ثم نضعها في
/// الـPDF كصورة عالية الدقة. الطابعات الحرارية تطبع الصور أصلًا.
class InvoicePdfBuilder {
  InvoicePdfBuilder._();

  /// عرض لوحة الرسم المنطقي (≈ 72mm بدقة 203 نقطة/إنش) ومعامل التكبير للدقة.
  static const double _canvasWidth = 576;
  static const double _pixelScale = 2;

  static const String _font = 'Tajawal';
  static const ui.Color _ink = ui.Color(0xFF000000);
  static const ui.Color _grey = ui.Color(0xFF555555);

  static String _money(Money m) => '${formatMoney(m)} ${AppInfo.currencyLabel}';

  static Future<Uint8List> build(
    Invoice invoice,
    AppSettings settings,
    PdfPageFormat format,
  ) async {
    final totals = invoice.totalsAt(DateTime.now(), settings.billingPolicy);
    final when = invoice.closedAt ?? invoice.createdAt;

    final r = _Receipt(_canvasWidth, _font);

    // ── الترويسة ──
    r.center(settings.loungeName, size: 44, bold: true);
    if (settings.loungePhone.trim().isNotEmpty) {
      r.gap(4);
      r.center(settings.loungePhone.trim(),
          size: 26, dir: ui.TextDirection.ltr);
    }
    r.gap(8);
    r.center('فاتورة رقم ${invoice.id}', size: 30);
    r.divider();
    r.row('الزبون', invoice.customerName);
    // التاريخ والوقت يُعرضان من اليسار لليمين حتى لا ينقلب ترتيب الأرقام.
    r.row('التاريخ', formatDateTime(when), valueDir: ui.TextDirection.ltr);
    r.divider();

    // ── اللعب ──
    if (invoice.playLines.isNotEmpty) {
      r.heading('اللعب');
      // نجمّع خطوط اللعب تحت الجهاز الواحد (الجهاز + عدد اللاعبين + السعر):
      // سطر عنوان بالاسم والمجموع، وتحته سطر لكل فترة (من/إلى، المدة، السعر).
      final groups = <String, List<PlayLine>>{};
      for (final l in invoice.playLines) {
        final key = '${l.resourceId}|${l.playerCount}|${l.hourlyRate.amount}';
        groups.putIfAbsent(key, () => []).add(l);
      }
      for (final lines in groups.values) {
        final first = lines.first;
        final total = lines.fold<int>(0, (sum, l) => sum + (l.charge?.amount ?? 0));
        r.row(
          first.resourceKind == ResourceKind.playstation
              ? '${first.resourceName} (${first.playerCount} ${first.playerCount == 1 ? 'لاعب' : 'لاعبين'})'
              : first.resourceName,
          _money(Money(total)),
        );
        for (final l in lines) {
          final end = l.endedAt;
          r.small([
            end == null
                ? 'من ${formatClock(l.startedAt)}'
                : 'من ${formatClock(l.startedAt)} إلى ${formatClock(end)}',
            describeMinutes(l.billedMinutes ?? 0),
            _money(l.charge ?? Money.zero),
          ].join('  •  '));
        }
      }
      r.divider();
    }

    // ── المشتريات ──
    if (invoice.itemLines.isNotEmpty) {
      r.heading('المشتريات');
      for (final i in invoice.itemLines) {
        r.row('${i.name} × ${i.quantity}', _money(i.total));
        if (i.quantity > 1) r.small('سعر الوحدة: ${_money(i.unitPrice)}');
      }
      r.divider();
    }

    // ── المجاميع ──
    if (invoice.playLines.isNotEmpty) {
      r.row('مجموع اللعب', _money(totals.playTotal));
    }
    if (invoice.itemLines.isNotEmpty) {
      r.row('مجموع المشتريات', _money(totals.itemsTotal));
    }
    if (totals.minimumAdjustment.amount > 0) {
      r.row('تعويض الحد الأدنى للفاتورة', _money(totals.minimumAdjustment));
    }
    if (totals.roundingDelta != 0) {
      r.row(
        'تقريب',
        '${totals.roundingDelta > 0 ? '+' : '-'}'
            '${formatMoney(Money(totals.roundingDelta.abs()))} ${AppInfo.currencyLabel}',
      );
    }
    r.gap(6);
    r.row('الإجمالي', _money(totals.finalTotal), bold: true, size: 40);
    r.divider();

    if (settings.invoiceFooter.trim().isNotEmpty) {
      r.center(settings.invoiceFooter.trim(), size: 28);
    }

    final image = await r.toPng(_pixelScale);

    // الصفحة بارتفاع الصورة تمامًا (إيصال رول بلا فراغ زائد).
    final contentWidth = format.availableWidth;
    final contentHeight = contentWidth * image.height / image.width;
    final pageFormat = format.copyWith(
      height: contentHeight + format.marginTop + format.marginBottom + 1,
    );

    final doc = pw.Document(title: 'فاتورة ${invoice.id}');
    final png = pw.MemoryImage(image.bytes);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Image(
          png,
          width: contentWidth,
          height: contentHeight,
          fit: pw.BoxFit.fill,
        ),
      ),
    );
    return doc.save();
  }
}

/// ناتج الرسم: بايتات PNG مع أبعادها بالبكسل.
class _Png {
  final Uint8List bytes;
  final int width;
  final int height;
  const _Png(this.bytes, this.width, this.height);
}

/// ناسخ إيصال بسيط: يقيس كل سطر بمحرّك نصوص فلتر (تشكيل عربي + bidi صحيحان)
/// ثم يرسم الجميع على لوحة بيضاء.
class _Receipt {
  final double width;
  final String fontFamily;

  final List<void Function(ui.Canvas)> _paints = [];
  final List<TextPainter> _painters = [];
  double _y = 0;

  _Receipt(this.width, this.fontFamily);

  TextStyle _style(double size, bool bold, ui.Color color) => TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
        color: color,
        height: 1.35,
      );

  TextPainter _painter(
    String text,
    TextStyle style, {
    required ui.TextDirection dir,
    required ui.TextAlign align,
    double minWidth = 0,
    required double maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: dir,
      textAlign: align,
      locale: const ui.Locale('ar'),
      textWidthBasis: TextWidthBasis.longestLine,
    )..layout(minWidth: minWidth, maxWidth: maxWidth);
    _painters.add(tp);
    return tp;
  }

  void _place(TextPainter tp, double x, double y) {
    _paints.add((c) => tp.paint(c, ui.Offset(x, y)));
  }

  void gap(double h) => _y += h;

  /// نص في منتصف السطر.
  void center(
    String text, {
    double size = 28,
    bool bold = false,
    ui.TextDirection dir = ui.TextDirection.rtl,
    ui.Color color = InvoicePdfBuilder._ink,
  }) {
    final tp = _painter(
      text,
      _style(size, bold, color),
      dir: dir,
      align: ui.TextAlign.center,
      minWidth: width,
      maxWidth: width,
    );
    _place(tp, 0, _y);
    _y += tp.height;
  }

  /// عنوان قسم: محاذاة لليمين وبخط عريض.
  void heading(String text) {
    final tp = _painter(
      text,
      _style(30, true, InvoicePdfBuilder._ink),
      dir: ui.TextDirection.rtl,
      align: ui.TextAlign.start,
      maxWidth: width,
    );
    _place(tp, width - tp.width, _y);
    _y += tp.height + 2;
  }

  /// سطر فرعي رمادي صغير (يلتف على أكثر من سطر عند الحاجة) محاذى لليمين.
  void small(String text) {
    final tp = _painter(
      text,
      _style(22, false, InvoicePdfBuilder._grey),
      dir: ui.TextDirection.rtl,
      align: ui.TextAlign.start,
      maxWidth: width,
    );
    _place(tp, width - tp.width, _y);
    _y += tp.height + 6;
  }

  /// سطر: التسمية على اليمين والقيمة على اليسار.
  void row(
    String label,
    String value, {
    bool bold = false,
    double size = 28,
    ui.TextDirection valueDir = ui.TextDirection.rtl,
  }) {
    final style = _style(size, bold, InvoicePdfBuilder._ink);
    final valueTp = _painter(
      value,
      style,
      dir: valueDir,
      align: ui.TextAlign.start,
      maxWidth: width * 0.55,
    );
    final labelTp = _painter(
      label,
      style,
      dir: ui.TextDirection.rtl,
      align: ui.TextAlign.start,
      maxWidth: width - valueTp.width - 16,
    );
    _place(valueTp, 0, _y);
    _place(labelTp, width - labelTp.width, _y);
    _y += (valueTp.height > labelTp.height ? valueTp.height : labelTp.height) + 4;
  }

  void divider() {
    _y += 8;
    final y = _y;
    _paints.add((c) => c.drawRect(
          ui.Rect.fromLTWH(0, y, width, 1.5),
          ui.Paint()..color = InvoicePdfBuilder._ink,
        ));
    _y += 1.5 + 8;
  }

  Future<_Png> toPng(double scale) async {
    final height = _y + 28; // هامش سفلي للتغذية بعد القص
    final pxW = (width * scale).round();
    final pxH = (height * scale).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, width, height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    for (final paint in _paints) {
      paint(canvas);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(pxW, pxH);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    picture.dispose();
    for (final tp in _painters) {
      tp.dispose();
    }
    if (data == null) {
      throw StateError('تعذّر رسم الفاتورة');
    }
    return _Png(data.buffer.asUint8List(), pxW, pxH);
  }
}