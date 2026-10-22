import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/text_styles.dart';

/// تنبيه ظاهر فوق أي صفحة (تذكير لعب جارٍ، موعد حجز...).
class AppAlert {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  /// زر ثانوي اختياري (مثل "فتح الفاتورة" بجانب "تمديد").
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;
  final VoidCallback? onDismiss;

  const AppAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.onDismiss,
  });
}

/// مركز تنبيهات واحد لكل التطبيق. عرض تنبيه بنفس [AppAlert.id] يستبدل القديم.
class AlertCenter extends ChangeNotifier {
  AlertCenter._();
  static final AlertCenter instance = AlertCenter._();

  final Map<String, AppAlert> _alerts = {};

  List<AppAlert> get alerts => _alerts.values.toList();

  void show(AppAlert alert) {
    _alerts[alert.id] = alert;
    notifyListeners();
  }

  void dismiss(String id) {
    final removed = _alerts.remove(id);
    if (removed == null) return;
    removed.onDismiss?.call();
    notifyListeners();
  }
}

/// يغلّف التطبيق ويرسم التنبيهات أعلى الشاشة. يجب أن يكون داخل Directionality
/// وThemeو (بدون Tooltip لأنه خارج الـ Navigator).
class AlertOverlay extends StatelessWidget {
  final Widget child;
  const AlertOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: ListenableBuilder(
                listenable: AlertCenter.instance,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in AlertCenter.instance.alerts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AlertCard(alert: a),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AppAlert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      elevation: 10,
      shadowColor: alert.color.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: alert.color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: alert.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(alert.icon, color: alert.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.title, style: AppTextStyles.heading3()),
                      const SizedBox(height: 2),
                      Text(alert.body,
                          style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // الأزرار في Wrap تحت النص: لا تتجاوز العرض في النوافذ الضيقة.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (alert.actionLabel != null && alert.onAction != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: alert.color,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 38),
                    ),
                    onPressed: () => alert.onAction!(),
                    child: Text(alert.actionLabel!),
                  ),
                if (alert.secondaryLabel != null && alert.onSecondary != null)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                    onPressed: () => alert.onSecondary!(),
                    child: Text(alert.secondaryLabel!),
                  ),
                TextButton(
                  onPressed: () => AlertCenter.instance.dismiss(alert.id),
                  child: const Text('إخفاء'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
