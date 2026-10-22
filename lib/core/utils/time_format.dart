String _two(int n) => n.toString().padLeft(2, '0');

/// نظام 12 ساعة: "8:00 م" / "8:30 ص" (ص = صباحًا، م = مساءً).
String formatClock(DateTime t) => formatHourMinute(t.hour, t.minute);

/// نفس [formatClock] من ساعة ودقيقة (0-23).
String formatHourMinute(int hour, int minute) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour < 12 ? 'ص' : 'م';
  return '$h12:${_two(minute)} $suffix';
}

/// yyyy-MM-dd
String formatDate(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

/// yyyy-MM-dd h:mm م
String formatDateTime(DateTime t) => '${formatDate(t)} ${formatClock(t)}';

/// hh:mm:ss (أو mm:ss إن كانت أقل من ساعة عند [compact]).
String formatDuration(Duration d, {bool compact = false}) {
  final total = d.isNegative ? -d : d;
  final h = total.inHours;
  final m = _two(total.inMinutes % 60);
  final s = _two(total.inSeconds % 60);
  if (compact && h == 0) return '$m:$s';
  return '${_two(h)}:$m:$s';
}

/// وصف نصي للمدة: "ساعة و20 دقيقة" / "45 دقيقة".
String describeMinutes(int minutes) {
  if (minutes < 60) return '$minutes دقيقة';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hours = h == 1 ? 'ساعة' : (h == 2 ? 'ساعتان' : '$h ساعات');
  return m == 0 ? hours : '$hours و$m دقيقة';
}

const Map<int, String> _arabicDayNames = {
  DateTime.monday: 'الاثنين',
  DateTime.tuesday: 'الثلاثاء',
  DateTime.wednesday: 'الأربعاء',
  DateTime.thursday: 'الخميس',
  DateTime.friday: 'الجمعة',
  DateTime.saturday: 'السبت',
  DateTime.sunday: 'الأحد',
};

String arabicDayName(DateTime t) => _arabicDayNames[t.weekday]!;
