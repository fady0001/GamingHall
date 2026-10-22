import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/dimensions.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/adaptive.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../auth/presentation/cubit/auth_cubit.dart';
import '../../bookings/presentation/pages/bookings_page.dart';
import '../../days/presentation/cubit/work_day_cubit.dart';
import '../../days/presentation/new_day_flow.dart';
import '../../home/presentation/pages/home_page.dart';
import '../../invoices/presentation/pages/invoice_history_page.dart';
import '../../menu/presentation/pages/menu_admin_page.dart';
import '../../reports/presentation/pages/reports_page.dart';
import '../../resources/presentation/pages/resources_admin_page.dart';
import '../../settings/presentation/cubit/settings_cubit.dart';
import '../../settings/presentation/pages/settings_page.dart';
import 'nav_cubit.dart';


class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final isManager = context.select((AuthCubit c) => c.state.isManager);
    final destination = context.watch<NavCubit>().state;

    final effective = (!isManager && destination.managerOnly) ? Destination.home : destination;
    if (effective != destination) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.read<NavCubit>().go(Destination.home);
      });
    }

    if (context.isCompact) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: Text(effective.label, style: AppTextStyles.heading3()),
        ),
        drawer: Drawer(
          width: Dimensions.sidebarWidth + 24,
          backgroundColor: AppColors.surface,
          child: SafeArea(
            child: _Sidebar(selected: effective, isManager: isManager, inDrawer: true),
          ),
        ),
        body: _page(effective),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(selected: effective, isManager: isManager),
          VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: _page(effective)),
        ],
      ),
    );
  }

  Widget _page(Destination d) {
    switch (d) {
      case Destination.home:
        return const HomePage(section: HomeSection.invoices);
      case Destination.devices:
        return const HomePage(section: HomeSection.devices);
      case Destination.history:
        return const InvoiceHistoryPage();
      case Destination.bookings:
        return const BookingsPage();
      case Destination.resources:
        return const ResourcesAdminPage();
      case Destination.menu:
        return const MenuAdminPage();
      case Destination.reports:
        return const ReportsPage();
      case Destination.settings:
        return const SettingsPage();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final Destination selected;
  final bool isManager;
  final bool inDrawer;
  const _Sidebar({required this.selected, required this.isManager, this.inDrawer = false});

  @override
  Widget build(BuildContext context) {
    final loungeName = context.select((SettingsCubit c) => c.state.settings.loungeName);
    final main = Destination.values
        .where((d) => !d.isAdminSection && (isManager || !d.managerOnly))
        .toList();
    final admin = isManager
        ? Destination.values.where((d) => d.isAdminSection).toList()
        : <Destination>[];

    return Container(
      width: Dimensions.sidebarWidth,
      color: AppColors.surface,
      padding: const EdgeInsets.all(Dimensions.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sports_esports_rounded, color: Colors.white),
              ),
              const SizedBox(width: Dimensions.spaceS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppInfo.englishName,
                        style: AppTextStyles.heading3(), overflow: TextOverflow.ellipsis),
                    Text(loungeName,
                        style: AppTextStyles.bodySmall(), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceL),
          Expanded(
            child: ListView(
              children: [
                for (final d in main) _item(context, d),
                if (admin.isNotEmpty) ...[
                  const SizedBox(height: Dimensions.spaceM),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Text('الإدارة', style: AppTextStyles.bodySmall(AppColors.textMuted)),
                  ),
                  for (final d in admin) _item(context, d),
                ],
                const SizedBox(height: Dimensions.spaceM),
                const _WorkDayCard(),
              ],
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          _BottomBar(isManager: isManager),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, Destination d) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _NavItem(
          destination: d,
          selected: d == selected,
          onTap: () {
            context.read<NavCubit>().go(d);
            if (inDrawer) Navigator.of(context).maybePop();
          },
        ),
      );
}

class _NavItem extends StatefulWidget {
  final Destination destination;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.18)
                : (_hovered ? AppColors.surfaceHigh : Colors.transparent),
            borderRadius: BorderRadius.circular(Dimensions.radiusM),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.destination.icon,
                size: 22,
                color: selected ? AppColors.primaryLight : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.destination.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge(
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
                  ).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _WorkDayCard extends StatelessWidget {
  const _WorkDayCard();

  @override
  Widget build(BuildContext context) {
    final day = context.select((WorkDayCubit c) => c.state.currentDay);
    final rolling = context.select((WorkDayCubit c) => c.state.isRollingOver);
    return Container(
      padding: const EdgeInsets.all(Dimensions.spaceM),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('يوم العمل الحالي', style: AppTextStyles.bodySmall()),
          const SizedBox(height: 4),
          Text(
            day == null ? '—' : day.label,
            style: AppTextStyles.heading3(),
          ),
          if (day != null)
            Text('بدأ ${formatClock(day.startedAt)}', style: AppTextStyles.bodySmall()),
          const SizedBox(height: Dimensions.spaceS),
          OutlinedButton.icon(
            onPressed: rolling ? null : () => startNewWorkDayFlow(context),
            icon: const Icon(Icons.event_repeat_rounded, size: 18),
            label: const Text('يوم عمل جديد'),
          ),
        ],
      ),
    );
  }
}


class _BottomBar extends StatelessWidget {
  final bool isManager;
  const _BottomBar({required this.isManager});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeCubit>().state;
    final color = isManager ? AppColors.primaryLight : AppColors.secondary;

    return Row(
      children: [
        IconButton(
          tooltip: 'الخروج',
          onPressed: () async {
            final confirmed = await showConfirmDialog(
              context,
              title: 'الخروج ',
              message: 'هل أنت متأكد أنك تريد الخروج؟',
              confirmLabel: 'الخروج',
              cancelLabel: 'إلغاء',
              icon: Icons.logout_rounded,
            );
            if (!confirmed || !context.mounted) return;
            context.read<NavCubit>().go(Destination.home);
            context.read<AuthCubit>().logout();
          },
          icon: const Icon(Icons.logout_rounded),
        ),
        IconButton(
          tooltip: isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
          onPressed: () => context.read<ThemeCubit>().toggle(),
          icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
        ),
        // Expanded (وليس Spacer + Flexible): الاثنان كانا يتقاسمان المساحة
        // المتبقية مناصفة فلا يبقى للاسم إلا بضعة بكسلات فيظهر مقطوعًا.
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(isManager ? 'المدير' : 'الموظف',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label(AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Icon(
                      isManager ? Icons.admin_panel_settings_rounded : Icons.badge_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}