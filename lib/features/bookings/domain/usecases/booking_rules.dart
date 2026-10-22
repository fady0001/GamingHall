import '../../../../core/utils/arabic_search.dart';
import '../../../../core/utils/time_format.dart';
import '../entities/booking.dart';

/// رقم الهاتف إلزامي: 10 أرقام ويبدأ بـ 09. يعيد رسالة الخطأ أو null إن صحّ.
String? validateBookingPhone(String phone) {
  final p = phone.trim();
  if (p.isEmpty) return 'اكتب رقم هاتف الزبون';
  if (!RegExp(r'^[0-9]+$').hasMatch(p)) return 'رقم الهاتف يجب أن يحتوي أرقامًا فقط';
  if (!p.startsWith('09')) return 'رقم الهاتف يجب أن يبدأ بـ 09';
  if (p.length != 10) return 'رقم الهاتف يجب أن يتكون من 10 أرقام';
  return null;
}

/// قبل كم دقيقة من الحجز يظهر الجهاز "محجوزة" ويُرسَل التذكير.
const Duration bookingLead = Duration(minutes: 60);

/// تداخل = (بداية الجديد < نهاية القديم) و(نهاية الجديد > بداية القديم).
/// حجزان متلاصقان (نهاية الأول = بداية الثاني) لا يتعارضان.
bool bookingsOverlap(
  DateTime newStart,
  DateTime newEnd,
  DateTime existingStart,
  DateTime existingEnd,
) {
  return newStart.isBefore(existingEnd) && newEnd.isAfter(existingStart);
}

/// أول حجز "قادم" على المورد [resourceId] يتداخل مع الفترة [start, end).
/// [excludeBookingId]: حجز يُتجاهَل (مثلًا الحجز الذي يجري تحويله إلى فاتورة الآن).
Booking? findConflictingBooking(
  Iterable<Booking> bookings,
  int resourceId,
  DateTime start,
  DateTime end, {
  int? excludeBookingId,
}) {
  Booking? first;
  for (final b in bookings) {
    if (b.status != BookingStatus.scheduled) continue;
    if (b.resourceId != resourceId) continue;
    // الحجز بوقت مفتوح لا يحجز الجهاز: الموظف يسأل اللاعب ويقرر بنفسه.
    if (b.isOpen) continue;
    if (excludeBookingId != null && b.id == excludeBookingId) continue;
    if (!bookingsOverlap(start, end, b.startAt, b.endAt)) continue;
    if (first == null || b.startAt.isBefore(first.startAt)) first = b;
  }
  return first;
}

/// الفترة التي يُعتبر فيها اللعب "حاجزًا" للجهاز عند فحص التعارض مع الحجوزات:
///  - وقت محدد: من الآن حتى نهاية المدة المحددة.
///  - وقت مفتوح (لا نهاية معروفة): من الآن حتى [bookingLead]، وهي النافذة التي
///    يظهر فيها الجهاز أصلًا "محجوزًا" في الشاشة الرئيسية.
DateTime playWindowEnd(DateTime now, int? plannedMinutes) => plannedMinutes != null
    ? now.add(Duration(minutes: plannedMinutes))
    : now.add(bookingLead);

/// رسالة رفض بدء/تمديد لعب لأنه يتداخل مع حجز.
String playBlockedByBookingMessage(
  Booking b,
  DateTime now, {
  required bool fixed,
  bool extending = false,
}) {
  final action = extending ? 'لا يمكن التمديد' : 'لا يمكن بدء اللعب';
  final head = '$action: "${b.resourceName}" محجوز لـ ${b.customerName} '
      '${b.isOpen ? 'من ${formatClock(b.startAt)} (وقت مفتوح)' : 'من ${formatClock(b.startAt)} إلى ${formatClock(b.endAt)}'}';
  final minutesLeft = b.startAt.difference(now).inMinutes;
  if (minutesLeft >= 1) {
    final tail = fixed
        ? 'اختر مدة لا تتجاوز ${describeMinutes(minutesLeft)} لينتهي اللعب قبل موعد الحجز.'
        : 'استخدم وقتًا محددًا لا يتجاوز ${describeMinutes(minutesLeft)} لينتهي قبل موعد الحجز.';
    return '$head. $tail';
  }
  return '$head. إن لم يحضر الزبون ألغِ الحجز من صفحة الحجوزات أولًا.';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// حجوزات يوم معيّن (حسب البداية) مع بحث بالاسم/الهاتف، مرتبة زمنيًا.
List<Booking> filterBookings(
  List<Booking> bookings, {
  DateTime? day,
  String query = '',
}) {
  final q = normalizeForSearch(query);
  final result = bookings.where((b) {
    if (day != null && !isSameDay(b.startAt, day)) return false;
    if (q.isNotEmpty &&
        !normalizeForSearch(b.customerName).contains(q) &&
        !b.phone.contains(query.trim())) {
      return false;
    }
    return true;
  }).toList();
  result.sort((a, b) => a.startAt.compareTo(b.startAt));
  return result;
}

/// حجوزات قادمة دخلت نافذة التذكير ولم يُعرض تذكيرها بعد ولم ينتهِ وقتها.
List<Booking> findBookingsDueForReminder(
  List<Booking> bookings,
  DateTime now, {
  Duration lead = bookingLead,
}) {
  return bookings
      .where((b) =>
          b.status == BookingStatus.scheduled &&
          b.reminderShownAt == null &&
          !now.isBefore(b.startAt.subtract(lead)) &&
          now.isBefore(b.endAt))
      .toList();
}

/// أقرب حجز قادم/جارٍ لمورد ضمن نافذة [lead].
Booking? nearestBookingFor(
  List<Booking> bookings,
  int resourceId,
  DateTime now, {
  Duration lead = bookingLead,
}) {
  Booking? best;
  for (final b in bookings) {
    if (b.status != BookingStatus.scheduled || b.resourceId != resourceId) {
      continue;
    }
    if (!now.isBefore(b.endAt)) continue; // انتهى وقته
    if (b.startAt.isAfter(now.add(lead))) continue; // بعيد
    if (best == null || b.startAt.isBefore(best.startAt)) best = b;
  }
  return best;
}
