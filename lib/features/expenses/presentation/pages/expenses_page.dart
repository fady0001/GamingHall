import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/month_names.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities/expense.dart';
import '../cubit/expenses_cubit.dart';
import '../widgets/expense_form_dialog.dart';

Color _kindColor(ExpenseKind kind) {
  switch (kind) {
    case ExpenseKind.maintenance:
      return AppColors.warning;
    case ExpenseKind.salaries:
      return AppColors.info;
    case ExpenseKind.supplies:
      return AppColors.secondary;
    case ExpenseKind.withdrawals:
      return AppColors.accent;
    case ExpenseKind.reserve:
      return AppColors.success;
  }
}

/// المصاريف (للمدير فقط): مصاريف الصالة والمسحوبات والاحتياطي حسب الشهر،
/// وسجل بمن غيّر ماذا ومتى. مشتريات البوفيه تأتي من فواتير المشتريات.
class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          PageHeader(
            title: 'المصاريف',
            subtitle:
                'مصاريف الصالة والمسحوبات والاحتياطي. مشتريات البوفيه تُحسب من فواتير المشتريات',
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Dimensions.spaceM),
            child: TabBar(
              tabs: [
                Tab(icon: Icon(Icons.account_balance_wallet_rounded), text: 'المصاريف'),
                Tab(icon: Icon(Icons.history_rounded), text: 'سجل التعديلات'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ExpensesTab(),
                _LogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── تبويب المصاريف ─────────────────────────

class _ExpensesTab extends StatefulWidget {
  const _ExpensesTab();

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  ExpenseKind? _filter;

  Future<void> _delete(Expense e) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف المصروف',
      message:
          'سيُحذف "${e.description.isEmpty ? e.kind.label : e.description}" '
          '(${formatMoneyWithUnit(e.amount)}) من القائمة ومن التقارير، '
          'ويبقى أثره في سجل التعديلات.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<ExpensesCubit>().delete(e.id);
      if (mounted) showAppSnack(context, 'تم حذف المصروف');
    } catch (err) {
      if (mounted) showAppSnack(context, friendlyError(err), error: true);
    }
  }

  Widget _monthBar(BuildContext context, ExpensesState state) {
    final cubit = context.read<ExpensesCubit>();
    return Row(
      children: [
        // في الواجهة العربية السهم نحو اليمين = الشهر السابق.
        IconButton(
          tooltip: 'الشهر السابق',
          onPressed: cubit.previousMonth,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        Flexible(
          child: Text(
            monthLabel(state.year, state.month),
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.heading3(),
          ),
        ),
        IconButton(
          tooltip: 'الشهر التالي',
          onPressed: state.canGoNext ? cubit.nextMonth : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        if (!state.isCurrentMonth)
          TextButton(
            onPressed: cubit.goToCurrentMonth,
            child: const Text('الشهر الحالي'),
          ),
        const Spacer(),
        SizedBox(
          height: Dimensions.buttonHeight,
          child: FilledButton.icon(
            onPressed: () => showExpenseFormDialog(context, initialKind: _filter),
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة مصروف'),
          ),
        ),
      ],
    );
  }

  Widget _summary(ExpensesState state) {
    return Wrap(
      spacing: Dimensions.spaceS,
      runSpacing: Dimensions.spaceS,
      children: [
        _SummaryCard(
          icon: Icons.summarize_rounded,
          label: 'إجمالي الشهر',
          value: formatMoneyWithUnit(state.total),
          color: AppColors.primaryLight,
        ),
        for (final k in ExpenseKind.values)
          _SummaryCard(
            icon: k.icon,
            label: k.label,
            value: formatMoneyWithUnit(state.totalFor(k)),
            color: _kindColor(k),
          ),
      ],
    );
  }

  Widget _filters() {
    return Wrap(
      spacing: Dimensions.spaceXS,
      runSpacing: Dimensions.spaceXS,
      children: [
        ChoiceChip(
          label: const Text('الكل'),
          selected: _filter == null,
          onSelected: (_) => setState(() => _filter = null),
        ),
        for (final k in ExpenseKind.values)
          ChoiceChip(
            avatar: Icon(k.icon, size: 18),
            label: Text(k.label),
            selected: _filter == k,
            onSelected: (_) => setState(() => _filter = k),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ExpensesCubit>().state;
    final shown = _filter == null
        ? state.expenses
        : state.expenses.where((e) => e.kind == _filter).toList();

    final header = <Widget>[
      _monthBar(context, state),
      const SizedBox(height: Dimensions.spaceM),
      _summary(state),
      const SizedBox(height: Dimensions.spaceM),
      _filters(),
      const SizedBox(height: Dimensions.spaceM),
    ];

    Widget body(int i) {
      if (i < header.length) return header[i];
      if (state.isLoading) {
        return const Padding(
          padding: EdgeInsets.all(Dimensions.spaceL),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (shown.isEmpty) {
        return EmptyState(
          icon: Icons.account_balance_wallet_rounded,
          title: 'لا توجد مصاريف في ${monthLabel(state.year, state.month)}',
          message: _filter == null
              ? 'اضغط "إضافة مصروف" لتسجيل صيانة أو رواتب أو مستلزمات أو مسحوبات أو احتياطي.'
              : 'لا توجد مصاريف من نوع "${_filter!.label}" في هذا الشهر.',
        );
      }
      final e = shown[i - header.length];
      return Padding(
        padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
        child: _ExpenseCard(
          expense: e,
          onEdit: () => showExpenseFormDialog(context, existing: e),
          onDelete: () => _delete(e),
        ),
      );
    }

    final itemCount = header.length + (state.isLoading || shown.isEmpty ? 1 : shown.length);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          Dimensions.spaceL, Dimensions.spaceM, Dimensions.spaceL, Dimensions.spaceL),
      itemCount: itemCount,
      itemBuilder: (context, i) => body(i),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Dimensions.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value, style: AppTextStyles.price(color, 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ExpenseCard({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final color = _kindColor(e.kind);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Dimensions.radiusM),
            ),
            child: Icon(e.kind.icon, color: color, size: 22),
          ),
          const SizedBox(width: Dimensions.spaceS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.description.isEmpty ? e.kind.label : e.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge(),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(label: e.kind.label, color: color, icon: e.kind.icon),
                    if (e.withdrawer != null && e.withdrawer!.isNotEmpty)
                      StatusBadge(
                        label: 'الساحب: ${e.withdrawer}',
                        color: AppColors.accent,
                        icon: Icons.person_rounded,
                      ),
                    Text('${arabicDayName(e.date)}  ${formatDate(e.date)}',
                        style: AppTextStyles.bodySmall(AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Dimensions.spaceS),
          Text(formatMoneyWithUnit(e.amount), style: AppTextStyles.price(color, 16)),
          IconButton(
            tooltip: 'تعديل',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── تبويب سجل التعديلات ─────────────────────────

const Map<String, String> _fieldLabels = {
  'kind': 'النوع',
  'amount': 'المبلغ',
  'description': 'الوصف',
  'date': 'التاريخ',
  'withdrawer': 'الساحب',
};

String _valueText(String key, Object? v) {
  if (v == null || (v is String && v.isEmpty)) return '—';
  switch (key) {
    case 'kind':
      return expenseKindFromName('$v').label;
    case 'amount':
      return formatMoneyWithUnit(Money((v as num).toInt()));
    default:
      return '$v';
  }
}

class _LogTab extends StatelessWidget {
  const _LogTab();

  @override
  Widget build(BuildContext context) {
    final list = context.watch<ExpensesCubit>().state.log;
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'لا يوجد سجل بعد',
        message: 'كل إضافة أو تعديل أو حذف للمصاريف يُسجَّل هنا: من فعلها ومتى والقيم قبل وبعد.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(Dimensions.spaceL),
      itemCount: list.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
        child: _LogCard(entry: list[i]),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final ExpenseLogEntry entry;
  const _LogCard({required this.entry});

  Color get _actionColor {
    switch (entry.action) {
      case ExpenseLogAction.added:
        return AppColors.success;
      case ExpenseLogAction.edited:
        return AppColors.info;
      case ExpenseLogAction.deleted:
        return AppColors.danger;
    }
  }

  IconData get _actionIcon {
    switch (entry.action) {
      case ExpenseLogAction.added:
        return Icons.add_circle_outline_rounded;
      case ExpenseLogAction.edited:
        return Icons.edit_rounded;
      case ExpenseLogAction.deleted:
        return Icons.delete_outline_rounded;
    }
  }

  /// أسطر التفاصيل: للتعديل الحقول التي تغيّرت فقط (من ← إلى)، وللإضافة
  /// والحذف ملخّص المصروف.
  List<String> _details() {
    final before = entry.before;
    final after = entry.after;
    if (entry.action == ExpenseLogAction.edited && before != null && after != null) {
      return [
        for (final key in _fieldLabels.keys)
          if (before[key] != after[key])
            '${_fieldLabels[key]}: من ${_valueText(key, before[key])} '
                'إلى ${_valueText(key, after[key])}',
      ];
    }
    final s = entry.snapshot;
    final withdrawer = s['withdrawer'];
    final description = s['description'];
    return [
      'المبلغ: ${_valueText('amount', s['amount'])}',
      if (withdrawer is String && withdrawer.isNotEmpty) 'الساحب: $withdrawer',
      if (description is String && description.isNotEmpty) 'الوصف: $description',
      'التاريخ: ${_valueText('date', s['date'])}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final kind = expenseKindFromName('${entry.snapshot['kind']}');
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
      accentColor: entry.action == ExpenseLogAction.deleted ? AppColors.danger : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: entry.action.label, color: _actionColor, icon: _actionIcon),
              const SizedBox(width: 8),
              StatusBadge(label: kind.label, color: _kindColor(kind), icon: kind.icon),
              const Spacer(),
              Text(formatDateTime(entry.at),
                  style: AppTextStyles.bodySmall(AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 6),
          Text('بواسطة: ${entry.actor}',
              style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
          const SizedBox(height: 2),
          for (final line in _details()) Text(line, style: AppTextStyles.bodyMedium()),
        ],
      ),
    );
  }
}
