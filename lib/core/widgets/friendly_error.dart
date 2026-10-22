/// يحوّل أي استثناء إلى رسالة عربية مفهومة للموظف (بدون "Bad state:" ونحوها).
String friendlyError(Object e) {
  if (e is StateError) return e.message;
  if (e is ArgumentError) return e.message?.toString() ?? 'قيمة غير صالحة';
  final text = e.toString();
  if (text.contains('DatabaseException') ||
      text.contains('SqfliteFfiException') ||
      text.contains('sqlite')) {
    return 'تعذّر تنفيذ العملية على قاعدة البيانات. حاول مرة أخرى.';
  }
  if (text.startsWith('Exception: ')) return text.substring(11);
  return text;
}
