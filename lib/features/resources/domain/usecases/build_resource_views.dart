import '../../../bookings/domain/entities/booking.dart';
import '../../../bookings/domain/usecases/booking_rules.dart';
import '../../../invoices/domain/entities/invoice.dart';
import '../entities/game_resource.dart';
import '../entities/resource_status.dart';

/// المورد مع حالته الحيّة ومن يلعب عليه.
class ResourceView {
  final GameResource resource;
  final ResourceStatus status;
  final PlayLine? runningLine;
  final Invoice? runningInvoice;
  final Booking? upcomingBooking;

  const ResourceView({
    required this.resource,
    required this.status,
    this.runningLine,
    this.runningInvoice,
    this.upcomingBooking,
  });
}

/// الأولوية: خارج الخدمة > مشغولة (لعب جارٍ) > محجوزة (حجز قريب) > متاحة.
/// ملاحظة: لو كان المورد "خارج الخدمة" وعليه لعب جارٍ (حالة نادرة: عُطّل أثناء
/// اللعب) تبقى الحالة "مشغولة" حتى تُسوّى الفاتورة، حتى لا يختفي الزبون من الشاشة.
List<ResourceView> buildResourceViews({
  required List<GameResource> resources,
  required List<Invoice> openInvoices,
  required List<Booking> bookings,
  required DateTime now,
}) {
  final running = <int, (PlayLine, Invoice)>{};
  for (final invoice in openInvoices) {
    for (final line in invoice.playLines) {
      if (line.isRunning) running[line.resourceId] = (line, invoice);
    }
  }

  return [
    for (final r in resources)
      () {
        final run = running[r.id];
        final booking = nearestBookingFor(bookings, r.id, now);
        final ResourceStatus status;
        if (run != null) {
          status = ResourceStatus.busy;
        } else if (r.outOfService) {
          status = ResourceStatus.outOfService;
        } else if (booking != null) {
          status = ResourceStatus.reserved;
        } else {
          status = ResourceStatus.available;
        }
        return ResourceView(
          resource: r,
          status: status,
          runningLine: run?.$1,
          runningInvoice: run?.$2,
          upcomingBooking: booking,
        );
      }(),
  ];
}
