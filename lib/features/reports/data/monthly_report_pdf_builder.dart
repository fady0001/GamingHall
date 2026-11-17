import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextWidthBasis;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/constants/app_info.dart';
import '../../../core/utils/month_names.dart';
import '../../../core/utils/number_format.dart';
import '../../../core/utils/time_format.dart';
import '../../settings/domain/entities/app_settings.dart';
import '../domain/entities/monthly_report.dart';

/// يبني التقرير الشهري PDF بحجم A4 عمودي.
///
/// نفس أسلوب الفاتورة تمامًا: مكتبة pdf لا تُشكّل العربي ولا ترتّب النص ثنائي
/// الاتجاه بشكل موثوق، فنرسم كل صفحة بمحرّك نصوص فلتر (خط Tajawal) ثم نضعها
/// في الـPDF كصورة عالية الدقة. نتيجة ذلك: النص لا يُحدَّد ولا يُبحث فيه.
class MonthlyReportPdfBuilder {
  MonthlyReportPdfBuilder._();

  /// معامل الدقة: صفحة 794×1123 منطقية ← ≈ 1985×2808 بكسل (≈ 240 نقطة/إنش).
  static const double _scale = 2.5;

  /// يرسم صفحات التقرير (PNG لكل صفحة) دون تغليفها في PDF.
  static Future<List<Uint8List>> renderPages(
    MonthlyReport r,
    AppSettings settings, {
    DateTime? now,
  }) {
    final doc = _Doc();
    _compose(doc, r, settings, now ?? DateTime.now());
    return doc.render(_scale);
  }

  static Future<Uint8List> build(
    MonthlyReport r,
    AppSettings settings, {
    DateTime? now,
  }) async {
    final pngs = await renderPages(r, settings, now: now);

    final format = PdfPageFormat.a4.copyWith(
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );
    final pdf = pw.Document(title: 'التقرير الشهري ${monthLabel(r.year, r.month)}');
    for (final png in pngs) {
      final image = pw.MemoryImage(png);
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) => pw.Image(
            image,
            width: format.width,
            height: format.height,
            fit: pw.BoxFit.fill,
          ),
        ),
      );
    }
    return pdf.save();
  }

  /// مبلغ مع الوحدة. الرقم داخل عزل LTR حتى تبقى إشارة السالب قبل الرقم.
  static String _m(int v) =>
      '\u2066${groupThousands(v)}\u2069 ${AppInfo.currencyLabel}';

  /// فرق بإشارة (+3 / -2) داخل عزل LTR حتى لا تنقلب الإشارة.
  static String _signed(int v) => '\u2066${v > 0 ? '+$v' : '$v'}\u2069';

  static void _compose(
      _Doc d, MonthlyReport r, AppSettings settings, DateTime now) {
    // ── الترويسة ──
    d.center(settings.loungeName, size: 34, bold: true);
    d.gap(2);
    d.center('التقرير الشهري  •  ${monthLabel(r.year, r.month)}',
        size: 24, bold: true, color: _Doc.accent);
    d.gap(2);
    d.center('تاريخ الإنشاء: ${formatDateTime(now)}',
        size: 16, color: _Doc.grey);
    d.gap(10);

    // ── 1) الإيراد ──
    d.section('الإيراد');
    d.row('إيراد الألعاب', _m(r.playRevenue));
    d.row('إيراد البار (المأكولات والمشروبات)', _m(r.barRevenue));
    if (r.adjustments != 0) {
      d.row('الحد الأدنى للفاتورة والتقريب', _m(r.adjustments));
    }
    d.row('إجمالي الإيراد', _m(r.totalRevenue), bold: true, band: true);
    d.note('عدد الفواتير المغلقة: ${r.invoiceCount}. تُحسب كل فاتورة في الشهر '
        'الذي بدأ فيه يوم عملها.');

    // ── 2) المصاريف حسب النوع ──
    d.gap(10);
    d.section('المصاريف');
    d.row('مشتريات البوفيه (المسدَّد خلال الشهر)', _m(r.buffetPurchases));
    d.row('صيانة', _m(r.maintenance));
    d.row('رواتب', _m(r.salaries));
    d.row('مستلزمات صالة', _m(r.supplies));
    d.row('إجمالي مصاريف التشغيل', _m(r.operatingExpenses),
        bold: true, band: true);

    d.gap(8);
    final profit = r.operatingProfit;
    d.row('ربح التشغيل', _m(profit),
        bold: true,
        size: 28,
        band: true,
        valueColor: profit < 0 ? _Doc.red : _Doc.green);
    d.note('ربح التشغيل = إجمالي الإيراد − مصاريف التشغيل.');

    // ── 3) المسحوبات والاحتياطي ──
    d.gap(10);
    d.section('المسحوبات والاحتياطي');
    d.row('المسحوبات', _m(r.withdrawals), bold: true);
    for (final w in r.withdrawers) {
      d.row(
        w.count > 1 ? '${w.name}  (${w.count} سحبات)' : w.name,
        _m(w.amount),
        indent: 22,
        size: 19,
        labelColor: _Doc.grey,
      );
    }
    d.row('الاحتياطي (وُضع هذا الشهر)', _m(r.reserve), bold: true);
    d.gap(6);
    final net = r.netAfterDistributions;
    d.row('الصافي بعد المسحوبات والاحتياطي', _m(net),
        bold: true,
        size: 28,
        band: true,
        valueColor: net < 0 ? _Doc.red : _Doc.green);
    d.gap(6);
    d.row('رصيد الاحتياطي التراكمي', _m(r.reserveBalance),
        size: 19, labelColor: _Doc.grey);
    d.row('مشتريات غير مسدّدة (غير مخصومة من الربح)', _m(r.unpaidPurchases),
        size: 19, labelColor: _Doc.grey);

    // ── 4) أكثر الأصناف مبيعًا ──
    d.gap(10);
    d.section('أكثر الأصناف مبيعًا');
    if (r.topItems.isEmpty) {
      d.note('لا توجد مبيعات أصناف في هذا الشهر.');
    } else {
      d.table(
        headers: const ['الصنف', 'الكمية', 'الإيراد'],
        widths: const [0.50, 0.18, 0.32],
        rows: [
          for (final i in r.topItems)
            [i.name, '${i.quantity}', _m(i.revenue)],
        ],
      );
    }

    // ── 5) فروقات الجرد ──
    d.gap(10);
    d.section('فروقات الجرد');
    if (r.stockDifferences.isEmpty) {
      d.note('لا توجد فروقات جرد في هذا الشهر.');
    } else {
      d.table(
        headers: const ['الصنف', 'الفرق (قطعة)', 'تكلفة القطعة', 'القيمة'],
        widths: const [0.38, 0.18, 0.20, 0.24],
        rows: [
          for (final s in r.stockDifferences)
            [s.name, _signed(s.difference), _m(s.unitCost), _m(s.value)],
        ],
      );
      d.row('صافي قيمة الفروقات', _m(r.stockDifferenceValue),
          bold: true,
          band: true,
          valueColor: r.stockDifferenceValue < 0 ? _Doc.red : _Doc.green);
      d.note('الفرق = الفعلي − المتوقع (سالب = نقص، موجب = زيادة). '
          'القيمة = الفرق × تكلفة القطعة الحالية للصنف.');
    }
  }
}

/// مستند من عدة صفحات: يقيس كل عنصر بمحرّك نصوص فلتر ثم يضعه في الصفحة الحالية،
/// وإن لم يتّسع ينتقل لصفحة جديدة. لا يُقسَّم السطر الواحد بين صفحتين.
class _Doc {
  static const double pageW = 794;
  static const double pageH = 1123;
  static const double margin = 44;
  static const double footerH = 34;
  static const double contentW = pageW - 2 * margin;

  static const String font = 'Tajawal';
  static const ui.Color ink = ui.Color(0xFF111111);
  static const ui.Color grey = ui.Color(0xFF5A5A5A);
  static const ui.Color accent = ui.Color(0xFF1F5F73);
  static const ui.Color green = ui.Color(0xFF1B7F3B);
  static const ui.Color red = ui.Color(0xFFB3261E);
  static const ui.Color band = ui.Color(0xFFE9F1F4);
  static const ui.Color zebra = ui.Color(0xFFF5F8F9);
  static const ui.Color line = ui.Color(0xFFC9D5DA);

  final List<List<void Function(ui.Canvas)>> _pages = [];
  final List<TextPainter> _painters = [];
  double _y = margin;

  _Doc() {
    _pages.add([]);
  }

  List<void Function(ui.Canvas)> get _cur => _pages.last;

  void _newPage() {
    _pages.add([]);
    _y = margin;
  }

  void _ensure(double height) {
    if (_y + height > pageH - margin - footerH) _newPage();
  }

  TextStyle _style(double size, bool bold, ui.Color color) => TextStyle(
        fontFamily: font,
        fontSize: size,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
        color: color,
        height: 1.35,
      );

  TextPainter _tp(
    String text,
    TextStyle style, {
    ui.TextDirection dir = ui.TextDirection.rtl,
    ui.TextAlign align = ui.TextAlign.start,
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

  void _paintText(TextPainter tp, double x, double y) {
    _cur.add((c) => tp.paint(c, ui.Offset(x, y)));
  }

  void _fill(double x, double y, double w, double h, ui.Color color,
      {double radius = 0}) {
    final rect = ui.Rect.fromLTWH(x, y, w, h);
    _cur.add((c) {
      final paint = ui.Paint()..color = color;
      if (radius > 0) {
        c.drawRRect(
            ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(radius)), paint);
      } else {
        c.drawRect(rect, paint);
      }
    });
  }

  void gap(double h) => _y += h;

  void center(
    String text, {
    double size = 22,
    bool bold = false,
    ui.Color color = ink,
  }) {
    final tp = _tp(text, _style(size, bold, color),
        align: ui.TextAlign.center, minWidth: contentW, maxWidth: contentW);
    _ensure(tp.height);
    _paintText(tp, margin, _y);
    _y += tp.height;
  }

  /// عنوان قسم: شريط ملوّن بنص أبيض عريض.
  void section(String title) {
    final tp = _tp(title, _style(22, true, const ui.Color(0xFFFFFFFF)),
        maxWidth: contentW - 24);
    final h = tp.height + 12;
    // لا نترك العنوان وحيدًا آخر الصفحة: نطلب مكان عنوان + سطر على الأقل.
    _ensure(h + 44);
    _fill(margin, _y, contentW, h, accent, radius: 6);
    _paintText(tp, pageW - margin - 12 - tp.width, _y + 6);
    _y += h + 6;
  }

  /// سطر: التسمية على اليمين والقيمة على اليسار.
  void row(
    String label,
    String value, {
    bool bold = false,
    double size = 21,
    double indent = 0,
    bool band = false,
    ui.Color labelColor = ink,
    ui.Color valueColor = ink,
    ui.TextDirection valueDir = ui.TextDirection.rtl,
  }) {
    final inner = contentW - 20 - indent;
    final valueTp = _tp(value, _style(size, bold, valueColor),
        dir: valueDir, maxWidth: inner * 0.5);
    final labelTp = _tp(label, _style(size, bold, labelColor),
        maxWidth: inner - valueTp.width - 16);
    final h = (valueTp.height > labelTp.height ? valueTp.height : labelTp.height) + 8;
    _ensure(h);
    if (band) _fill(margin, _y, contentW, h, _Doc.band, radius: 4);
    final top = _y + 4;
    _paintText(valueTp, margin + 10, top);
    _paintText(labelTp, pageW - margin - 10 - indent - labelTp.width, top);
    _y += h + 2;
  }

  /// ملاحظة صغيرة رمادية (تلتف على أكثر من سطر).
  void note(String text) {
    final tp = _tp(text, _style(16, false, grey), maxWidth: contentW - 20);
    _ensure(tp.height + 6);
    _paintText(tp, pageW - margin - 10 - tp.width, _y + 2);
    _y += tp.height + 6;
  }

  /// جدول: العمود الأول (النص) على اليمين، وباقي الأعمدة أرقام في الوسط.
  /// ترويسة الجدول تتكرر عند الانتقال لصفحة جديدة.
  void table({
    required List<String> headers,
    required List<double> widths,
    required List<List<String>> rows,
  }) {
    const pad = 8.0;

    // حواف الأعمدة من اليمين.
    final lefts = <double>[];
    final colW = <double>[];
    var right = pageW - margin;
    for (final w in widths) {
      final cw = contentW * w;
      colW.add(cw);
      lefts.add(right - cw);
      right -= cw;
    }

    double rowHeight(List<TextPainter> cells) {
      var h = 0.0;
      for (final c in cells) {
        if (c.height > h) h = c.height;
      }
      return h + 12;
    }

    List<TextPainter> makeCells(List<String> values, bool bold, ui.Color color) {
      return [
        for (var i = 0; i < values.length; i++)
          _tp(
            values[i],
            _style(19, bold, color),
            dir: ui.TextDirection.rtl,
            align: i == 0 ? ui.TextAlign.start : ui.TextAlign.center,
            minWidth: colW[i] - 2 * pad,
            maxWidth: colW[i] - 2 * pad,
          ),
      ];
    }

    void drawHeader() {
      final cells = makeCells(headers, true, const ui.Color(0xFF0F3D4B));
      final h = rowHeight(cells);
      _ensure(h);
      _fill(margin, _y, contentW, h, const ui.Color(0xFFD6E6EC), radius: 4);
      for (var i = 0; i < cells.length; i++) {
        _paintText(cells[i], lefts[i] + pad, _y + 6);
      }
      _y += h;
    }

    drawHeader();
    for (var n = 0; n < rows.length; n++) {
      final cells = makeCells(rows[n], false, ink);
      final h = rowHeight(cells);
      if (_y + h > pageH - margin - footerH) {
        _newPage();
        drawHeader();
      }
      if (n.isOdd) _fill(margin, _y, contentW, h, zebra);
      for (var i = 0; i < cells.length; i++) {
        _paintText(cells[i], lefts[i] + pad, _y + 6);
      }
      _y += h;
    }
    final y = _y;
    _cur.add((c) => c.drawRect(
          ui.Rect.fromLTWH(margin, y, contentW, 1),
          ui.Paint()..color = line,
        ));
    _y += 8;
  }

  /// يرسم الصفحات (مع ترقيمها) ويعيد PNG لكل صفحة.
  Future<List<Uint8List>> render(double scale) async {
    final total = _pages.length;
    final out = <Uint8List>[];
    for (var p = 0; p < total; p++) {
      final footer = _tp(
        'صفحة ${p + 1} من $total',
        _style(15, false, grey),
        align: ui.TextAlign.center,
        minWidth: contentW,
        maxWidth: contentW,
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(scale);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, pageW, pageH),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      for (final paint in _pages[p]) {
        paint(canvas);
      }
      footer.paint(canvas, ui.Offset(margin, pageH - margin - footer.height + 10));

      final picture = recorder.endRecording();
      final image =
          await picture.toImage((pageW * scale).round(), (pageH * scale).round());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (data == null) {
        throw StateError('تعذّر رسم صفحة التقرير');
      }
      out.add(data.buffer.asUint8List());
    }
    for (final tp in _painters) {
      tp.dispose();
    }
    return out;
  }
}
