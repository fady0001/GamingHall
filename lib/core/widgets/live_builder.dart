import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../di/clock_cubit.dart';

/// يعيد بناء نفسه فقط كل ثانية (بدل إعادة بناء الصفحة كلها) ويمنح الـ builder
/// الوقت الحالي. استخدمه حول عدّاد أو مبلغ حيّ فقط.
class LiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, DateTime now) builder;
  const LiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ClockCubit, DateTime>(
      builder: (context, now) => builder(context, now),
    );
  }
}
