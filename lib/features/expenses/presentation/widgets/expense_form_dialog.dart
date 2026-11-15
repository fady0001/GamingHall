import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/money_parser.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/money_field.dart';
import '../../domain/entities/expense.dart';
import '../cubit/expenses_cubit.dart';

/// إضافة مصروف ([existing] == null) أو تعديله. يرجع true إن تم الحفظ.
Future<bool> showExpenseFormDialog(
  BuildContext context, {
  Expense? existing,
  ExpenseKind? initialKind,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ExpenseFormDialog(existing: existing, initialKind: initialKind),
  );
  return ok ?? false;
}

class _ExpenseFormDialog extends StatefulWidget {
  final Expense? existing;
  final ExpenseKind? initialKind;
  const _ExpenseFormDialog({this.existing, this.initialKind});

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  late ExpenseKind _kind;
  late DateTime _date;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _withdrawer = TextEditingController();

  String? _amountError;
  String? _descriptionError;
  String? _withdrawerError;
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    if (e != null) {
      _kind = e.kind;
      _date = e.date;
      _amount.text = groupThousands(e.amount.amount);
      _description.text = e.description;
      _withdrawer.text = e.withdrawer ?? '';
    } else {
      _kind = widget.initialKind ?? ExpenseKind.supplies;
      _date = DateTime(now.year, now.month, now.day);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _withdrawer.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(now.year - 3),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    final money = parseMoney(_amount.text);
    final description = _description.text.trim();
    final withdrawer = _withdrawer.text.trim();

    String? amountError;
    String? descriptionError;
    String? withdrawerError;
    if (money == null || money.amount <= 0) {
      amountError = 'اكتب مبلغًا أكبر من صفر';
    }
    if (_kind.descriptionRequired && description.isEmpty) {
      descriptionError = ExpenseErrors.description;
    }
    if (_kind.needsWithdrawer && withdrawer.isEmpty) {
      withdrawerError = ExpenseErrors.withdrawer;
    }
    if (amountError != null || descriptionError != null || withdrawerError != null) {
      setState(() {
        _amountError = amountError;
        _descriptionError = descriptionError;
        _withdrawerError = withdrawerError;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _amountError = null;
      _descriptionError = null;
      _withdrawerError = null;
      _error = null;
    });
    final input = ExpenseInput(
      kind: _kind,
      amount: money ?? Money.zero,
      description: description,
      date: _date,
      withdrawer: _kind.needsWithdrawer ? withdrawer : null,
    );
    try {
      final cubit = context.read<ExpensesCubit>();
      final existing = widget.existing;
      if (existing == null) {
        await cubit.add(input);
      } else {
        await cubit.update(existing.id, input);
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

  @override
  Widget build(BuildContext context) {
    final names = context.select((ExpensesCubit c) => c.state.withdrawerNames);

    return AppDialog(
      title: _isEdit ? 'تعديل مصروف' : 'إضافة مصروف',
      icon: _isEdit ? Icons.edit_rounded : Icons.add_card_rounded,
      width: 520,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(_isEdit ? 'حفظ التعديل' : 'حفظ'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('نوع المصروف', style: AppTextStyles.label(AppColors.textSecondary)),
          const SizedBox(height: Dimensions.spaceXS),
          Wrap(
            spacing: Dimensions.spaceXS,
            runSpacing: Dimensions.spaceXS,
            children: [
              for (final k in ExpenseKind.values)
                ChoiceChip(
                  avatar: Icon(k.icon, size: 18),
                  label: Text(k.label),
                  selected: _kind == k,
                  onSelected: _busy ? null : (_) => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceM),
          MoneyField(
            controller: _amount,
            label: 'المبلغ',
            errorText: _amountError,
            autofocus: !_isEdit,
            enabled: !_busy,
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
          ),
          if (_kind.needsWithdrawer) ...[
            const SizedBox(height: Dimensions.spaceM),
            TextField(
              controller: _withdrawer,
              enabled: !_busy,
              maxLength: 60,
              onChanged: (_) {
                if (_withdrawerError != null) setState(() => _withdrawerError = null);
              },
              decoration: InputDecoration(
                labelText: 'اسم الساحب',
                errorText: _withdrawerError,
                prefixIcon: const Icon(Icons.person_rounded),
                counterText: '',
              ),
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: Dimensions.spaceXS),
              Wrap(
                spacing: Dimensions.spaceXS,
                runSpacing: Dimensions.spaceXXS,
                children: [
                  for (final n in names.take(8))
                    ActionChip(
                      label: Text(n),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _withdrawer.text = n;
                                _withdrawerError = null;
                              }),
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: Dimensions.spaceM),
          TextField(
            controller: _description,
            enabled: !_busy,
            maxLength: 200,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) {
              if (_descriptionError != null) setState(() => _descriptionError = null);
            },
            decoration: InputDecoration(
              labelText: _kind.descriptionRequired ? 'الوصف' : 'الوصف (اختياري)',
              errorText: _descriptionError,
              prefixIcon: const Icon(Icons.notes_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: Dimensions.spaceM),
          InkWell(
            borderRadius: BorderRadius.circular(Dimensions.radiusM),
            onTap: _busy ? null : _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'التاريخ',
                prefixIcon: Icon(Icons.event_rounded),
              ),
              child: Text(
                '${arabicDayName(_date)}  ${formatDate(_date)}',
                style: AppTextStyles.bodyLarge(),
              ),
            ),
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
