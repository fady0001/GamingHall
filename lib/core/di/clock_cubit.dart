import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// ساعة التطبيق: تنبض كل ثانية. كل العدّادات الحيّة تقرأ منها بدل أن يملك
/// كل عدّاد مؤقته الخاص (أداء أفضل واتساق في الوقت المعروض بين الشاشات).
class ClockCubit extends Cubit<DateTime> {
  ClockCubit() : super(DateTime.now()) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) emit(DateTime.now());
    });
  }

  Timer? _timer;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
