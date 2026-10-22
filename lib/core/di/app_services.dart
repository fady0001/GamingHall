import '../backup/backup_service.dart';
import '../database/app_database.dart';
import '../../features/auth/data/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/bookings/data/booking_repository_impl.dart';
import '../../features/bookings/domain/repositories/booking_repository.dart';
import '../../features/days/data/work_day_repository_impl.dart';
import '../../features/days/domain/repositories/work_day_repository.dart';
import '../../features/invoices/data/invoice_repository_impl.dart';
import '../../features/invoices/domain/repositories/invoice_repository.dart';
import '../../features/menu/data/menu_repository_impl.dart';
import '../../features/menu/domain/repositories/menu_repository.dart';
import '../../features/reports/data/report_repository_impl.dart';
import '../../features/reports/domain/repositories/report_repository.dart';
import '../../features/resources/data/resource_repository_impl.dart';
import '../../features/resources/domain/repositories/resource_repository.dart';
import '../../features/settings/data/settings_repository_impl.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';

/// كل المستودعات والخدمات المبنية على قاعدة البيانات المفتوحة. تُنشأ مرة واحدة
/// بعد التحقق من الترخيص.
class AppServices {
  final AppDatabase database;
  final SettingsRepository settings;
  final AuthRepository auth;
  final ResourceRepository resources;
  final MenuRepository menu;
  final WorkDayRepository days;
  final InvoiceRepository invoices;
  final BookingRepository bookings;
  final ReportRepository reports;
  final BackupService backup;

  AppServices._({
    required this.database,
    required this.settings,
    required this.auth,
    required this.resources,
    required this.menu,
    required this.days,
    required this.invoices,
    required this.bookings,
    required this.reports,
    required this.backup,
  });

  static Future<AppServices> create() async {
    final db = await AppDatabase.open();
    return AppServices._(
      database: db,
      settings: SettingsRepositoryImpl(db),
      auth: AuthRepositoryImpl(db),
      resources: ResourceRepositoryImpl(db),
      menu: MenuRepositoryImpl(db),
      days: WorkDayRepositoryImpl(db),
      invoices: InvoiceRepositoryImpl(db),
      bookings: BookingRepositoryImpl(db),
      reports: ReportRepositoryImpl(db),
      backup: BackupService(db),
    );
  }
}
