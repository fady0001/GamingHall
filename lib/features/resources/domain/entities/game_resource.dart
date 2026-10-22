import 'package:flutter/widgets.dart';

import '../../../../core/domain/value_objects/money.dart';
import 'resource_kind.dart';

const Object _keep = Object();

/// جهاز أو طاولة أو لعبة. للبلايستيشن فقط يختلف سعر الساعة حسب عدد اللاعبين
/// (1 إلى 4)؛ لغيره سعر واحد (أول سعر) وعدد اللاعبين 1.
class GameResource {
  static const int maxPlayersLimit = 4;

  final int id;
  final String name;
  final ResourceKind kind;

  /// نوع الطاولة كما حدده المدير (بلياردو، هوكي...). null لغير الطاولات.
  final String? typeName;

  /// أقصى عدد لاعبين يمكن اختياره عند بدء اللعب (1 إلى 4).
  final int maxPlayers;

  /// فهرس 0 = لاعب واحد ... 3 = أربعة لاعبين.
  final List<Money> hourlyRates;

  /// خارج الخدمة (صيانة/تعطيل مؤقت): يبقى ظاهرًا لكن لا يمكن تشغيله.
  final bool outOfService;

  /// الإخفاء النهائي من النظام (بدل الحذف، حتى تبقى الفواتير القديمة سليمة).
  final bool isActive;

  const GameResource({
    required this.id,
    required this.name,
    required this.kind,
    this.typeName,
    required this.maxPlayers,
    required this.hourlyRates,
    this.outOfService = false,
    this.isActive = true,
  }) : assert(hourlyRates.length == maxPlayersLimit);

  /// الاسم الذي يُعرض كنوع: نوع الطاولة إن وُجد وإلا اسم الفئة.
  String get typeLabel =>
      (typeName != null && typeName!.trim().isNotEmpty) ? typeName! : kind.label;

  IconData get icon => iconForTypeName(typeName, kind);

  Money rateFor(int players) {
    final index = players.clamp(1, maxPlayersLimit) - 1;
    return hourlyRates[index];
  }

  GameResource copyWith({
    String? name,
    ResourceKind? kind,
    Object? typeName = _keep,
    int? maxPlayers,
    List<Money>? hourlyRates,
    bool? outOfService,
    bool? isActive,
  }) {
    return GameResource(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      typeName: identical(typeName, _keep) ? this.typeName : typeName as String?,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      hourlyRates: hourlyRates ?? this.hourlyRates,
      outOfService: outOfService ?? this.outOfService,
      isActive: isActive ?? this.isActive,
    );
  }
}
