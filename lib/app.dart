import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/alerts/alert_center.dart';
import 'core/backup/backup_service.dart';
import 'core/constants/app_info.dart';
import 'core/di/app_services.dart';
import 'core/di/clock_cubit.dart';
import 'core/platform/alert_notifier.dart';
import 'core/platform/window_service.dart';
import 'core/security/license_lock_page.dart';
import 'core/security/license_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/dimensions.dart';
import 'core/theme/theme_cubit.dart';
import 'core/theme/text_styles.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/pages/account_missing_page.dart';
import 'features/auth/presentation/pages/role_gate_page.dart';
import 'features/auth/presentation/pages/setup_page.dart';
import 'features/bookings/presentation/cubit/bookings_cubit.dart';
import 'features/days/presentation/cubit/work_day_cubit.dart';
import 'features/invoices/presentation/cubit/invoices_cubit.dart';
import 'features/menu/presentation/cubit/menu_cubit.dart';
import 'features/reminders/presentation/reminders_host.dart';
import 'features/reports/presentation/cubit/reports_cubit.dart';
import 'features/resources/presentation/cubit/devices_board_cubit.dart';
import 'features/resources/presentation/cubit/resources_cubit.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/shell/presentation/app_shell.dart';
import 'features/shell/presentation/nav_cubit.dart';

class _BootResult {
  final LicenseCheckResult license;
  final String licensePath;
  final AppServices? services;
  const _BootResult(this.license, this.licensePath, this.services);
}

/// جذر التطبيق: يتحقق من الترخيص، يفتح قاعدة البيانات، ثم يبني المزوّدين.
/// تفعيل الترخيص من شاشة القفل يعيد التهيئة هنا دون إغلاق التطبيق.
class GamingHallApp extends StatefulWidget {
  const GamingHallApp({super.key});

  @override
  State<GamingHallApp> createState() => _GamingHallAppState();
}

class _GamingHallAppState extends State<GamingHallApp> {
  late Future<_BootResult> _boot;

  @override
  void initState() {
    super.initState();
    _boot = _bootstrap();
  }

  Future<_BootResult> _bootstrap() async {
    final license = await LicenseService.validate();
    final path = await LicenseService.licenseFilePath();
    if (!license.isValid) return _BootResult(license, path, null);

    final services = await AppServices.create();
    await AlertNotifier.instance.init();
    services.backup.startAutoBackup();
    return _BootResult(license, path, services);
  }

  void _retry() => setState(() => _boot = _bootstrap());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootResult>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _shell(_ErrorPage(error: snapshot.error!, onRetry: _retry));
        }
        final boot = snapshot.data;
        if (boot == null) return _shell(const _SplashPage());

        if (!boot.license.isValid) {
          return _shell(LicenseLockPage(
            result: boot.license,
            licenseFilePath: boot.licensePath,
            onActivated: _retry,
          ));
        }
        return _Providers(services: boot.services!, child: const _MainApp());
      },
    );
  }

  /// MaterialApp بسيط لشاشات ما قبل الدخول (تحميل/ترخيص/خطأ).
  Widget _shell(Widget home) {
    return MaterialApp(
      title: AppInfo.englishName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.dark,
      home: home,
    );
  }
}

class _Providers extends StatelessWidget {
  final AppServices services;
  final Widget child;
  const _Providers({required this.services, required this.child});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<BackupService>.value(
      value: services.backup,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ClockCubit()),
          BlocProvider(create: (_) => NavCubit()),
          BlocProvider(create: (_) => ThemeCubit(services.database)),
          BlocProvider(create: (_) => SettingsCubit(services.settings)),
          BlocProvider(create: (_) => AuthCubit(services.auth)),
          BlocProvider(create: (_) => ResourcesCubit(services.resources)),
          BlocProvider(create: (_) => MenuCubit(services.menu)),
          BlocProvider(create: (_) => WorkDayCubit(services.days)),
          BlocProvider(create: (_) => InvoicesCubit(services.invoices, services.days)),
          BlocProvider(create: (_) => BookingsCubit(services.bookings)),
          BlocProvider(
            create: (ctx) => DevicesBoardCubit(
              ctx.read<ResourcesCubit>(),
              ctx.read<InvoicesCubit>(),
              ctx.read<BookingsCubit>(),
            ),
          ),
          BlocProvider(
            create: (ctx) => ReportsCubit(services.reports, () {
              final day = ctx.read<WorkDayCubit>().state.currentDay;
              final now = DateTime.now();
              return day?.startedAt ?? DateTime(now.year, now.month, now.day);
            }),
          ),
        ],
        child: child,
      ),
    );
  }
}

class _MainApp extends StatelessWidget {
  const _MainApp();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, bool>(
      builder: (context, isDark) => MaterialApp(
        title: AppInfo.englishName,
        debugShowCheckedModeBanner: false,
        navigatorKey: WindowService.instance.navigatorKey,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // forMode يضبط AppColors.isDark قبل بناء أي صفحة.
        theme: AppTheme.forMode(isDark),
        builder: (context, child) => RemindersHost(
          child: AlertOverlay(child: child ?? const SizedBox.shrink()),
        ),
        // المفتاح يجبر الصفحة الرئيسية على إعادة البناء كاملة عند تبديل الوضع،
        // لأن الألوان تُقرأ من AppColors مباشرة.
        home: KeyedSubtree(
          key: ValueKey(isDark),
          child: BlocBuilder<AuthCubit, AuthState>(
            builder: (context, auth) {
              if (auth.hasManagerAccount == null) return const _SplashPage();
              if (auth.accountMissing) return const AccountMissingPage();
              if (auth.hasManagerAccount == false) return const SetupPage();
              if (!auth.roleSelected) return const RoleGatePage();
              return const AppShell();
            },
          ),
        ),
      ),
    );
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.sports_esports_rounded, size: 46, color: Colors.white),
            ),
            const SizedBox(height: Dimensions.spaceL),
            Text(AppInfo.englishName, style: AppTextStyles.heading1()),
            const SizedBox(height: Dimensions.spaceM),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorPage({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(Dimensions.spaceL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.danger),
                const SizedBox(height: Dimensions.spaceM),
                Text('تعذّر تشغيل التطبيق', style: AppTextStyles.heading1()),
                const SizedBox(height: Dimensions.spaceS),
                Text(
                  'حدث خطأ أثناء فتح قاعدة البيانات. أغلق أي نسخة أخرى من التطبيق '
                  'وحاول مرة أخرى. إن استمر الخطأ تواصل مع الدعم الفني.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge(AppColors.textSecondary),
                ),
                const SizedBox(height: Dimensions.spaceM),
                SelectableText('$error',
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.bodySmall(AppColors.textMuted)),
                const SizedBox(height: Dimensions.spaceL),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
