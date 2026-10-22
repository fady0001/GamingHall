import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/money_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/money_field.dart';
import '../../domain/entities/game_resource.dart';
import '../../domain/entities/resource_kind.dart';
import '../cubit/resources_cubit.dart';

/// إضافة أو تعديل جهاز. الفئة تُحدَّد من زر "إضافة" في قسمها (أو من المورد
/// نفسه عند التعديل):
///  - بلايستيشن: اسم + سعر الساعة لكل عدد لاعبين (1 إلى 4).
///  - طاولة: اسم + نوع (من الأنواع المفعّلة) + سعر واحد.
///  - كمبيوتر / لعبة أخرى: اسم + سعر واحد (بدون عدد لاعبين).
Future<bool> showResourceFormDialog(
  BuildContext context, {
  GameResource? existing,
  ResourceKind kind = ResourceKind.playstation,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ResourceFormDialog(existing: existing, kind: existing?.kind ?? kind),
  );
  return ok ?? false;
}

class _ResourceFormDialog extends StatefulWidget {
  final GameResource? existing;
  final ResourceKind kind;
  const _ResourceFormDialog({this.existing, required this.kind});

  @override
  State<_ResourceFormDialog> createState() => _ResourceFormDialogState();
}

class _ResourceFormDialogState extends State<_ResourceFormDialog> {
  final _name = TextEditingController();
  final List<TextEditingController> _rates =
      List.generate(GameResource.maxPlayersLimit, (_) => TextEditingController());
  String? _typeName;
  bool _busy = false;
  String? _error;
  String? _nameError;
  String? _typeError;
  final List<String?> _rateErrors = List.filled(GameResource.maxPlayersLimit, null);

  ResourceKind get _kind => widget.kind;
  bool get _isEdit => widget.existing != null;
  bool get _perPlayer => _kind.hasPlayerPricing;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name.text = e?.name ?? '';
    _typeName = e?.typeName;
    if (e != null) {
      for (var i = 0; i < GameResource.maxPlayersLimit; i++) {
        _rates[i].text = formatMoney(e.hourlyRates[i]);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _rates) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final tableTypes = context.read<ResourcesCubit>().state.tableTypes;
    setState(() {
      _error = null;
      _nameError = _name.text.trim().isEmpty ? 'اكتب الاسم' : null;
      _typeError = (_kind == ResourceKind.table && (_typeName == null || _typeName!.isEmpty))
          ? (tableTypes.isEmpty ? 'أضف نوع طاولة أولًا من صفحة الطاولات' : 'اختر نوع الطاولة')
          : null;
      for (var i = 0; i < _rateErrors.length; i++) {
        _rateErrors[i] = null;
      }
    });

    final rates = <Money>[];
    var valid = _nameError == null && _typeError == null;
    final count = _perPlayer ? GameResource.maxPlayersLimit : 1;
    for (var i = 0; i < count; i++) {
      final m = parseMoney(_rates[i].text);
      if (m == null || m.amount <= 0) {
        _rateErrors[i] = 'أدخل السعر';
        valid = false;
      } else {
        rates.add(m);
      }
    }
    if (!valid) {
      setState(() {});
      return;
    }

    // غير البلايستيشن: سعر واحد يُنسخ للأربعة (لا يُستخدم عدد لاعبين أصلًا).
    final full = [
      for (var i = 0; i < GameResource.maxPlayersLimit; i++)
        _perPlayer ? rates[i] : rates.first,
    ];
    final maxPlayers = _perPlayer ? GameResource.maxPlayersLimit : 1;
    final typeName = _kind == ResourceKind.table ? _typeName : null;

    setState(() => _busy = true);
    final cubit = context.read<ResourcesCubit>();
    try {
      if (_isEdit) {
        await cubit.update(widget.existing!.copyWith(
          name: _name.text.trim(),
          typeName: typeName,
          maxPlayers: maxPlayers,
          hourlyRates: full,
        ));
      } else {
        await cubit.add(GameResource(
          id: 0,
          name: _name.text.trim(),
          kind: _kind,
          typeName: typeName,
          maxPlayers: maxPlayers,
          hourlyRates: full,
        ));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  String get _title {
    final verb = _isEdit ? 'تعديل' : 'إضافة';
    switch (_kind) {
      case ResourceKind.playstation:
        return '$verb شاشة بلايستيشن';
      case ResourceKind.computer:
        return '$verb كمبيوتر';
      case ResourceKind.table:
        return '$verb طاولة';
      case ResourceKind.other:
        return '$verb لعبة';
    }
  }

  String get _nameHint {
    switch (_kind) {
      case ResourceKind.playstation:
        return 'الاسم (مثال: PS 1)';
      case ResourceKind.computer:
        return 'الاسم (مثال: كمبيوتر 3)';
      case ResourceKind.table:
        return 'الاسم (مثال: طاولة 2)';
      case ResourceKind.other:
        return 'اسم اللعبة';
    }
  }

  String _playersLabel(int n) =>
      n == 1 ? 'لاعب واحد' : (n == 2 ? 'لاعبان' : '$n لاعبين');

  @override
  Widget build(BuildContext context) {
    final tableTypes = context.watch<ResourcesCubit>().state.tableTypes;
    // عند التعديل: نوع الطاولة الحالي يبقى ظاهرًا حتى لو عُطّل لاحقًا.
    final typeNames = {
      for (final t in tableTypes) t.name,
      if (_typeName != null && _typeName!.isNotEmpty) _typeName!,
    }.toList();

    return AppDialog(
      title: _title,
      icon: _kind.icon,
      width: 520,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(_isEdit ? 'حفظ التعديلات' : 'إضافة'),
        ),
      ],
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: _nameHint,
                prefixIcon: const Icon(Icons.label_rounded),
                errorText: _nameError,
                counterText: '',
              ),
            ),
            if (_kind == ResourceKind.table) ...[
              const SizedBox(height: Dimensions.spaceM),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: typeNames.contains(_typeName) ? _typeName : null,
                decoration: InputDecoration(
                  labelText: 'نوع الطاولة',
                  prefixIcon: const Icon(Icons.category_rounded),
                  errorText: _typeError,
                ),
                items: [
                  for (final n in typeNames)
                    DropdownMenuItem(
                      value: n,
                      child: Text(n, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _typeName = v),
              ),
            ],
            const SizedBox(height: Dimensions.spaceL),
            Text(_perPlayer ? 'سعر الساعة حسب عدد اللاعبين' : 'سعر الساعة',
                style: AppTextStyles.heading3()),
            const SizedBox(height: Dimensions.spaceS),
            if (_perPlayer)
              for (var i = 0; i < GameResource.maxPlayersLimit; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
                  child: MoneyField(
                    controller: _rates[i],
                    label: _playersLabel(i + 1),
                    errorText: _rateErrors[i],
                    enabled: !_busy,
                  ),
                )
            else
              MoneyField(
                controller: _rates[0],
                label: 'سعر الساعة',
                errorText: _rateErrors[0],
                enabled: !_busy,
              ),
            Text(
              'الوقت يُحسب لأقرب دقيقة، ويمكن للموظف اختيار وقت مفتوح أو محدد عند بدء اللعب.',
              style: AppTextStyles.bodySmall(),
            ),
            if (_error != null) ...[
              const SizedBox(height: Dimensions.spaceM),
              Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
            ],
          ],
      ),
    );
  }
}
