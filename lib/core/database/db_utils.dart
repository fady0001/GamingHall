/// التواريخ تُخزَّن كنص ISO-8601 بالتوقيت المحلي (يُرتَّب أبجديًا كما يُرتَّب
/// زمنيًا، ويسمح بالتجميع حسب اليوم عبر substr في SQL).
String dbTime(DateTime t) => t.toIso8601String();

DateTime parseDbTime(Object? value) => DateTime.parse(value as String);

DateTime? parseDbTimeOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

bool dbBool(Object? value) => value == 1 || value == true;

int boolToDb(bool value) => value ? 1 : 0;

/// هل الخطأ ناتج عن مخالفة قيد التفرّد (UNIQUE)؟
bool isUniqueViolation(Object error) =>
    error.toString().contains('UNIQUE constraint failed');
