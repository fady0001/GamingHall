import 'package:flutter/material.dart';

/// الحالات الأربع التي يراها الموظف بلمحة:
///  - متاحة: يمكن حجزها واللعب عليها الآن.
///  - مشغولة: يوجد من يلعب عليها حاليًا.
///  - محجوزة: لها حجز مسبق قريب (خلال الساعة القادمة).
///  - خارج الخدمة: معطّلة أو في الصيانة (يضبطها المدير).
enum ResourceStatus { available, busy, reserved, outOfService }

extension ResourceStatusX on ResourceStatus {
  String get label {
    switch (this) {
      case ResourceStatus.available:
        return 'متاحة';
      case ResourceStatus.busy:
        return 'مشغولة';
      case ResourceStatus.reserved:
        return 'محجوزة';
      case ResourceStatus.outOfService:
        return 'خارج الخدمة';
    }
  }

  IconData get icon {
    switch (this) {
      case ResourceStatus.available:
        return Icons.check_circle_rounded;
      case ResourceStatus.busy:
        return Icons.play_circle_rounded;
      case ResourceStatus.reserved:
        return Icons.bookmark_rounded;
      case ResourceStatus.outOfService:
        return Icons.block_rounded;
    }
  }
}
