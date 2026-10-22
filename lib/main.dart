import 'package:flutter/material.dart';

import 'app.dart';
import 'core/platform/window_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowService.instance.init();
  runApp(const GamingHallApp());
}
