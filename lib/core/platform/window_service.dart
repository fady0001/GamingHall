import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_info.dart';
import '../theme/dimensions.dart';
import '../widgets/app_dialog.dart';
import 'alert_notifier.dart';
import '../../features/invoices/presentation/cubit/invoices_cubit.dart';

/// إعداد نافذة سطح المكتب وأيقونة شريط النظام (System Tray).
///
/// زر الإغلاق (X) لا يُنهي التطبيق: يخفي النافذة فقط ويبقى التطبيق شغّالًا
/// بالخلفية فتستمر التنبيهات (تذكير اللعب المفتوح، الحجوزات). الإنهاء الحقيقي
/// من أيقونة الشريط ← "إغلاق التطبيق نهائيًا"، وفيه تأكيد يحذّر إن كان هناك
/// لعب جارٍ.
class WindowService with WindowListener, TrayListener {
  WindowService._();
  static final WindowService instance = WindowService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool _asking = false;
  bool _trayReady = false;
  bool _hintShown = false;

  /// يُضبط من app.dart بعد فتح قاعدة البيانات: إيقاف المؤقتات وإغلاق القاعدة
  /// بشكل سليم قبل إنهاء العملية.
  Future<void> Function()? beforeExit;

  Future<void> init() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1366, 820),
      minimumSize: Size(Dimensions.minWindowWidth, Dimensions.minWindowHeight),
      center: true,
      title: AppInfo.englishName,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await _initTray();
  }

  Future<void> _initTray() async {
    try {
      trayManager.addListener(this);
      await trayManager.setIcon('assets/icons/tray_icon.ico');
      await trayManager.setToolTip(AppInfo.englishName);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show_window', label: 'إظهار التطبيق'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'إغلاق التطبيق نهائيًا'),
      ]));
      _trayReady = true;
    } catch (e) {
      // بدون أيقونة لا نخفي النافذة أبدًا (حتى لا يضيع التطبيق)؛ يعود الإغلاق
      // العادي مع تأكيد.
      _trayReady = false;
      debugPrint('تعذّر تفعيل أيقونة شريط النظام: $e');
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await _showWindow();
      case 'exit_app':
        await _showWindow();
        await _confirmAndQuit();
    }
  }

  @override
  void onWindowClose() async {
    if (_trayReady) {
      await windowManager.hide();
      if (!_hintShown) {
        _hintShown = true;
        await AlertNotifier.instance.showToast(
          title: AppInfo.englishName,
          body: 'التطبيق ما زال يعمل بالخلفية لتصلك التنبيهات. '
              'افتحه من أيقونته بجانب الساعة.',
        );
      }
      return;
    }
    await _confirmAndQuit();
  }

  Future<void> _confirmAndQuit() async {
    if (_asking) return;
    final context = navigatorKey.currentContext;
    if (context == null) {
      await _destroy();
      return;
    }
    _asking = true;
    try {
      var running = 0;
      try {
        running = context
            .read<InvoicesCubit>()
            .state
            .open
            .fold<int>(0, (sum, i) => sum + i.runningLines.length);
      } catch (_) {}

      final confirmed = await showConfirmDialog(
        context,
        title: 'إغلاق التطبيق؟',
        message: running > 0
            ? 'يوجد $running لعب جارٍ الآن. الوقت يستمر بالعدّ حتى لو أُغلق '
                'التطبيق، لكن تنبيهات التذكير ستتوقف حتى تفتحه من جديد.'
            : 'هل تريد إغلاق التطبيق؟',
        confirmLabel: 'إغلاق التطبيق',
        danger: running > 0,
        icon: Icons.power_settings_new_rounded,
      );
      if (confirmed) await _destroy();
    } finally {
      _asking = false;
    }
  }

  /// إنهاء سريع وآمن: نخفي النافذة فورًا (حتى لا يبدو التطبيق متجمّدًا)، ننظّف
  /// ما يلزم بمهلة قصوى لكل خطوة، ثم ننهي العملية مباشرة بدل انتظار إيقاف
  /// محرّك Flutter الذي قد يطول عدّة ثوانٍ.
  Future<void> _destroy() async {
    try {
      await windowManager.hide();
    } catch (_) {}

    Future<void> guarded(Future<void> Function() step, int seconds) async {
      try {
        await step().timeout(Duration(seconds: seconds));
      } catch (e) {
        debugPrint('خطوة إنهاء متعثّرة: $e');
      }
    }

    final cleanup = beforeExit;
    if (cleanup != null) await guarded(cleanup, 4);
    await guarded(AlertNotifier.instance.dispose, 2);
    await guarded(() => trayManager.destroy(), 2);

    exit(0);
  }
}
