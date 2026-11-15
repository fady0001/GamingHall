/// أسماء الأشهر بالشامي (كانون الثاني، شباط...). الفهرس 0 = كانون الثاني.
const List<String> shamiMonthNames = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

/// اسم الشهر ([month] من 1 إلى 12).
String shamiMonthName(int month) => shamiMonthNames[(month - 1).clamp(0, 11)];

/// "تشرين الثاني 2026"
String monthLabel(int year, int month) => '${shamiMonthName(month)} $year';
