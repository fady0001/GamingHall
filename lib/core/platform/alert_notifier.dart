import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_info.dart';

/// نغمة تنبيه + إشعار ويندوز. أي فشل (لا صوت، الإشعارات معطّلة...) يُسجَّل فقط
/// ولا يوقف التطبيق.
class AlertNotifier {
  AlertNotifier._();
  static final AlertNotifier instance = AlertNotifier._();

  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;

  Future<void> init() async {
    try {
      await localNotifier.setup(
        appName: AppInfo.englishName,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _ready = true;
    } catch (e) {
      debugPrint('local_notifier setup failed: $e');
    }
  }

  /// يُستدعى عند إنهاء التطبيق لتحرير مشغّل الصوت.
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (e) {
      debugPrint('audio dispose failed: $e');
    }
  }

  Future<void> playChime() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/chime.wav'));
    } catch (e) {
      debugPrint('chime failed: $e');
    }
  }

  /// إشعار سطح مكتب (الضغط عليه يُظهر نافذة التطبيق).
  Future<void> showToast({required String title, required String body}) async {
    if (!_ready) return;
    try {
      final toast = LocalNotification(title: title, body: body, silent: true);
      toast.onClick = () async {
        await windowManager.show();
        await windowManager.focus();
      };
      await toast.show();
    } catch (e) {
      debugPrint('toast failed: $e');
    }
  }
}
