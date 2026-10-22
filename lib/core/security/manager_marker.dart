import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// علامة "كان هنا حساب مدير": تُكتب في مكانين خارج مجلد قاعدة البيانات. إن
/// اختفت قاعدة البيانات (حذفها موظف مثلًا) وبقيت العلامة، فالتطبيق يرفض إنشاء
/// حساب مدير جديد بصمت ويطلب استعادة نسخة احتياطية.
class ManagerMarker {
  ManagerMarker._();

  static const String _name = '.manager_registered';

  static Future<List<File>> _files() async {
    final files = <File>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      files.add(File(p.join(docs.path, 'GamingHall', _name)));
    } catch (_) {}
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      files.add(File(p.join(local, 'GamingHall', _name)));
    }
    return files;
  }

  static Future<bool> exists() async {
    for (final f in await _files()) {
      try {
        if (await f.exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<void> write() async {
    for (final f in await _files()) {
      try {
        await f.parent.create(recursive: true);
        await f.writeAsString(DateTime.now().toIso8601String(), flush: true);
      } catch (_) {}
    }
  }
}
