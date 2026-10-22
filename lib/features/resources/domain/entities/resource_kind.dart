import 'package:flutter/material.dart';

/// فئة المورد. أربع فئات ثابتة؛ ونوع الطاولة (بلياردو، هوكي...) يحدده المدير
/// بنفسه ويُخزَّن اسمًا نصيًا في المورد (`typeName`).
///
/// التخزين بالاسم، والأسماء القديمة (billiards, pingPong...) تُقرأ كـ "طاولة".
enum ResourceKind { playstation, computer, table, other }

/// مجموعات العرض في لوحة الأجهزة.
enum ResourceGroup { consoles, computers, tables, other }

extension ResourceGroupX on ResourceGroup {
  String get label {
    switch (this) {
      case ResourceGroup.consoles:
        return 'شاشات البلايستيشن';
      case ResourceGroup.computers:
        return 'الكمبيوترات';
      case ResourceGroup.tables:
        return 'الطاولات';
      case ResourceGroup.other:
        return 'ألعاب أخرى';
    }
  }

  IconData get icon {
    switch (this) {
      case ResourceGroup.consoles:
        return Icons.sports_esports_rounded;
      case ResourceGroup.computers:
        return Icons.computer_rounded;
      case ResourceGroup.tables:
        return Icons.table_restaurant_rounded;
      case ResourceGroup.other:
        return Icons.extension_rounded;
    }
  }
}

extension ResourceKindX on ResourceKind {
  String get label {
    switch (this) {
      case ResourceKind.playstation:
        return 'بلايستيشن';
      case ResourceKind.computer:
        return 'كمبيوتر';
      case ResourceKind.table:
        return 'طاولة';
      case ResourceKind.other:
        return 'لعبة أخرى';
    }
  }

  ResourceGroup get group {
    switch (this) {
      case ResourceKind.playstation:
        return ResourceGroup.consoles;
      case ResourceKind.computer:
        return ResourceGroup.computers;
      case ResourceKind.table:
        return ResourceGroup.tables;
      case ResourceKind.other:
        return ResourceGroup.other;
    }
  }

  IconData get icon {
    switch (this) {
      case ResourceKind.playstation:
        return Icons.sports_esports_rounded;
      case ResourceKind.computer:
        return Icons.computer_rounded;
      case ResourceKind.table:
        return Icons.table_restaurant_rounded;
      case ResourceKind.other:
        return Icons.extension_rounded;
    }
  }

  /// أسعار حسب عدد اللاعبين (1 إلى 4)؟ للبلايستيشن فقط. الباقي سعر واحد.
  bool get hasPlayerPricing => this == ResourceKind.playstation;

  /// أقصى عدد لاعبين: 4 للبلايستيشن، وللباقي 1 (بلا تحديد لاعبين أصلًا).
  int get suggestedMaxPlayers => hasPlayerPricing ? 4 : 1;
}

ResourceKind resourceKindFromName(String name) {
  for (final k in ResourceKind.values) {
    if (k.name == name) return k;
  }
  switch (name) {
    case 'billiards':
    case 'pingPong':
    case 'airHockey':
    case 'foosball':
    case 'cards':
      return ResourceKind.table;
  }
  return ResourceKind.other;
}

/// الفئة من مفتاح نوع محفوظ على خط لعب: اسم فئة (playstation...) أو اسم قديم،
/// وأي اسم آخر هو اسم نوع طاولة أضافه المدير (فيكون الفئة "طاولة").
ResourceKind kindFromTypeKey(String key) {
  for (final k in ResourceKind.values) {
    if (k.name == key) return k;
  }
  switch (key) {
    case 'billiards':
    case 'pingPong':
    case 'airHockey':
    case 'foosball':
    case 'cards':
      return ResourceKind.table;
  }
  return ResourceKind.table;
}

/// أنواع الطاولات بلا أيقونات خاصة: كل الطاولات تأخذ أيقونة فئتها.
IconData iconForTypeName(String? typeName, ResourceKind kind) => kind.icon;

/// تسمية مفتاح نوع محفوظ في التقارير: اسم نوع طاولة، أو اسم فئة (playstation...).
String labelForTypeKey(String key) {
  for (final k in ResourceKind.values) {
    if (k.name == key) return k.label;
  }
  switch (key) {
    case 'billiards':
      return 'بلياردو';
    case 'pingPong':
      return 'بينغ بونغ';
    case 'airHockey':
      return 'هوكي';
    case 'foosball':
      return 'فوتبول طاولة';
    case 'cards':
      return 'طاولة ورق';
  }
  return key;
}
