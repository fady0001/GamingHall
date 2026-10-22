import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_styles.dart';
import '../utils/time_format.dart';

const List<String> _monthNames = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// رؤوس الأيام، الأسبوع يبدأ من السبت (كما في بقية التطبيق).
const List<String> _weekHeads = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

/// نافذة منبثقة (فوق الصفحة، لا شاشة جديدة) لاختيار فترة من روزنامة.
/// الأيام بعد [lastDate] (أو قبل [firstDate]) معطّلة ولا تُختار.
/// تُرجع [DateTimeRange] بيوم البداية ويوم النهاية (كلاهما مشمول)، أو null عند الإلغاء.
Future<DateTimeRange?> showDateRangeDialog({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialRange,
  String title = 'اختيار الفترة',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _DateRangeDialog(
      firstDate: _d(firstDate),
      lastDate: _d(lastDate),
      initialRange: initialRange,
      title: title,
    ),
  );
}

class _DateRangeDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;
  final String title;

  const _DateRangeDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
    required this.title,
  });

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _month; // أول يوم من الشهر المعروض
  bool _pickingMonth = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRange;
    if (r != null) {
      _start = _clamp(_d(r.start));
      _end = _clamp(_d(r.end));
      if (_end!.isBefore(_start!)) _end = _start;
    }
    final focus = _end ?? widget.lastDate;
    _month = DateTime(focus.year, focus.month, 1);
  }

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  bool _enabled(DateTime d) =>
      !d.isBefore(widget.firstDate) && !d.isAfter(widget.lastDate);

  bool get _canGoPrev =>
      DateTime(_month.year, _month.month, 1).isAfter(
          DateTime(widget.firstDate.year, widget.firstDate.month, 1));

  bool get _canGoNext =>
      DateTime(_month.year, _month.month, 1).isBefore(
          DateTime(widget.lastDate.year, widget.lastDate.month, 1));

  void _tap(DateTime d) {
    if (!_enabled(d)) return;
    setState(() {
      if (_start == null || _end != null) {
        // بداية فترة جديدة.
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        // اختار يومًا أقدم من البداية: يصير هو البداية.
        _start = d;
      } else {
        _end = d;
      }
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  void _confirm() {
    final s = _start;
    if (s == null) return;
    Navigator.of(context).pop(DateTimeRange(start: s, end: _end ?? s));
  }

  String get _summary {
    final s = _start;
    if (s == null) return 'اضغط على يوم البداية ثم يوم النهاية';
    final e = _end;
    if (e == null) return '${formatDate(s)}  (اختر يوم النهاية أو اضغط تطبيق ليوم واحد)';
    if (e == s) return formatDate(s);
    final days = e.difference(s).inDays + 1;
    return '${formatDate(s)}  →  ${formatDate(e)}  •  $days يوم';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.radiusL),
          side: BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dimensions.spaceM),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: AppTextStyles.heading3()),
                const SizedBox(height: 4),
                Text(_summary, style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                const SizedBox(height: Dimensions.spaceS),
                _monthHeader(),
                const SizedBox(height: 4),
                if (_pickingMonth) _monthGrid() else _daysGrid(),
                const SizedBox(height: Dimensions.spaceS),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _start == null ? null : _confirm,
                      child: const Text('تطبيق'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- رأس الشهر

  Widget _monthHeader() {
    final label = _pickingMonth
        ? '${_month.year}'
        : '${_monthNames[_month.month - 1]} ${_month.year}';
    final canPrev = _pickingMonth
        ? _month.year > widget.firstDate.year
        : _canGoPrev;
    final canNext = _pickingMonth
        ? _month.year < widget.lastDate.year
        : _canGoNext;
    void prev() => _pickingMonth
        ? setState(() => _month = DateTime(_month.year - 1, _month.month, 1))
        : _shiftMonth(-1);
    void next() => _pickingMonth
        ? setState(() => _month = DateTime(_month.year + 1, _month.month, 1))
        : _shiftMonth(1);

    return Row(
      children: [
        // في الواجهة العربية السابق على اليمين والتالي على اليسار.
        IconButton(
          tooltip: _pickingMonth ? 'السنة السابقة' : 'الشهر السابق',
          onPressed: canPrev ? prev : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(Dimensions.radiusS),
            onTap: () => setState(() => _pickingMonth = !_pickingMonth),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: AppTextStyles.heading3()),
                  const SizedBox(width: 4),
                  Icon(
                    _pickingMonth
                        ? Icons.arrow_drop_up_rounded
                        : Icons.arrow_drop_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _pickingMonth ? 'السنة التالية' : 'الشهر التالي',
          onPressed: canNext ? next : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ اختيار شهر

  Widget _monthGrid() {
    final year = _month.year;
    return Column(
      children: [
        for (var row = 0; row < 4; row++)
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(child: _monthCell(year, row * 3 + col + 1)),
            ],
          ),
      ],
    );
  }

  Widget _monthCell(int year, int month) {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final enabled = !last.isBefore(widget.firstDate) && !first.isAfter(widget.lastDate);
    final selected = month == _month.month;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
        onTap: enabled
            ? () => setState(() {
                  _month = DateTime(year, month, 1);
                  _pickingMonth = false;
                })
            : null,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : null,
            borderRadius: BorderRadius.circular(Dimensions.radiusM),
          ),
          child: Text(
            _monthNames[month - 1],
            style: AppTextStyles.bodyMedium(
              selected
                  ? Colors.white
                  : (enabled ? AppColors.textPrimary : AppColors.textMuted.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ شبكة الأيام

  Widget _daysGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // السبت = 0 ... الجمعة = 6.
    final offset = (first.weekday - DateTime.saturday) % 7;
    final cells = <DateTime?>[
      for (var i = 0; i < offset; i++) null,
      for (var day = 1; day <= daysInMonth; day++) DateTime(_month.year, _month.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Column(
      children: [
        Row(
          children: [
            for (final h in _weekHeads)
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: Center(
                    child: Text(h, style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                  ),
                ),
              ),
          ],
        ),
        for (var r = 0; r < cells.length ~/ 7; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++) Expanded(child: _dayCell(cells[r * 7 + c])),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(DateTime? day) {
    const height = 40.0;
    if (day == null) return const SizedBox(height: height);

    final enabled = _enabled(day);
    final start = _start;
    final end = _end;
    final isStart = start != null && day == start;
    final isEnd = end != null && day == end;
    final endpoint = isStart || isEnd;

    final hasRange = start != null && end != null && end.isAfter(start);
    // الواجهة من اليمين لليسار: النصف الأيمن = جهة الأيام الأقدم.
    final bandRight = hasRange && day.isAfter(start) && !day.isAfter(end);
    final bandLeft = hasRange && day.isBefore(end) && !day.isBefore(start);
    final band = AppColors.primary.withValues(alpha: AppColors.isDark ? 0.24 : 0.16);

    final isToday = day == _d(DateTime.now());

    Color textColor;
    if (endpoint) {
      textColor = Colors.white;
    } else if (!enabled) {
      textColor = AppColors.textMuted.withValues(alpha: 0.45);
    } else {
      textColor = AppColors.textPrimary;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => _tap(day) : null,
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(child: ColoredBox(color: bandRight ? band : Colors.transparent)),
                  Expanded(child: ColoredBox(color: bandLeft ? band : Colors.transparent)),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: endpoint ? AppColors.primary : null,
                border: (!endpoint && isToday)
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: AppTextStyles.bodyMedium(textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
