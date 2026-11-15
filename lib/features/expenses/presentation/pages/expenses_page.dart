import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/month_names.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/entities/buffet_payment.dart';
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

/// مشتريات البوفيه (عرض فقط): لونها وأيقونتها خاصان بها لتتميّز عن أنواع المصاريف.
const Color _buffetColor = Color(0xFFFB923C);
const IconData _buffetIcon = Icons.shopping_cart_rounded;

/// أقصى عرض للمحتوى على الشاشات العريضة (حتى لا تتمدد البطاقات بلا فائدة).
const double _maxContentWidth = 1200;

/// حواف الصفحة: أصغر على الهاتف، ويتوسّط المحتوى على الشاشات العريضة جدًا.
EdgeInsets _pagePadding(double width) {
  final base = width < Breakpoints.phone ? Dimensions.spaceM : Dimensions.spaceL;
  final side = width > _maxContentWidth + 2 * base ? (width - _maxContentWidth) / 2 : base;
  return EdgeInsets.fromLTRB(side, base, side, base);
}

/// المصاريف (للمدير فقط): مصاريف الصالة والمسحوبات والاحتياطي حسب الشهر،
/// وسجل بمن غيّر ماذا ومتى. مشتريات البوفيه تظهر بلا أزرار تعديل (تُدار من
/// صفحة المخزون والجرد) وتُحسب مع المصاريف.
class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final side = context.isPhone ? Dimensions.spaceM : Dimensions.spaceL;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'المصاريف',
            subtitle:
                'مصاريف الصالة والمسحوبات والاحتياطي، مع مشتريات البوفيه المسدَّدة (تُدار من صفحة المخزون والجرد)',
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            // تبويبان فقط: نجمعهما عند البداية بدل أن يتباعدا على عرض الشاشة.
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.account_balance_wallet_rounded), text: 'المصاريف'),
                Tab(icon: Icon(Icons.history_rounded), text: 'سجل التعديلات'),
              ],
            ),
          ),
          const Expanded(
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

  /// عرض مشتريات البوفيه فقط (للعرض، بلا تعديل).
  bool _buffetOnly = false;

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

  /// شريط الشهر وزر الإضافة. على العرض الضيق: المنتقي بعرض كامل والزر تحته.
  Widget _toolbar(BuildContext context, ExpensesState state, bool narrow) {
    final cubit = context.read<ExpensesCubit>();
    final nav = _MonthNavigator(
      label: monthLabel(state.year, state.month),
      expand: narrow,
      onPrevious: cubit.previousMonth,
      onNext: state.canGoNext ? cubit.nextMonth : null,
    );
    final backToCurrent = state.isCurrentMonth
        ? null
        : TextButton(
            onPressed: cubit.goToCurrentMonth,
            child: const Text('الشهر الحالي'),
          );
    final add = SizedBox(
      height: Dimensions.buttonHeight,
      child: FilledButton.icon(
        onPressed: () => showExpenseFormDialog(context, initialKind: _filter),
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة مصروف'),
      ),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          nav,
          if (backToCurrent != null) Align(alignment: AlignmentDirectional.centerStart, child: backToCurrent),
          const SizedBox(height: Dimensions.spaceS),
          add,
        ],
      );
    }
    return Row(
      children: [
        nav,
        if (backToCurrent != null) ...[
          const SizedBox(width: Dimensions.spaceXS),
          backToCurrent,
        ],
        const Spacer(),
        add,
      ],
    );
  }

  /// ملخّص الشهر: 7 بطاقات بعرض متساوٍ (7 / 4 / 2 / 1 أعمدة حسب العرض).
  Widget _summary(ExpensesState state) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = Dimensions.spaceS;
        final cols = c.maxWidth >= 1100
            ? 7
            : (c.maxWidth >= 640 ? 4 : (c.maxWidth >= 380 ? 2 : 1));
        // floor: تجنّب فرق كسري صغير يرمي آخر بطاقة لسطر جديد.
        final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        final cards = <Widget>[
          _SummaryCard(
            icon: Icons.summarize_rounded,
            label: 'إجمالي الشهر',
            value: formatMoneyWithUnit(state.total),
            color: AppColors.primaryLight,
            emphasized: true,
          ),
          for (final k in ExpenseKind.values) ...[
            _SummaryCard(
              icon: k.icon,
              label: k.label,
              value: formatMoneyWithUnit(state.totalFor(k)),
              color: _kindColor(k),
            ),
            // مشتريات البوفيه بعد مصاريف التشغيل (صيانة، رواتب، مستلزمات).
            if (k == ExpenseKind.supplies)
              _SummaryCard(
                icon: _buffetIcon,
                label: 'مشتريات البوفيه (المدفوع)',
                value: formatMoneyWithUnit(state.buffetTotal),
                color: _buffetColor,
              ),
          ],
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }

  /// فلاتر النوع بسطر واحد قابل للتمرير أفقيًا (لا تتكدس على الهاتف).
  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('الكل'),
            selected: _filter == null && !_buffetOnly,
            onSelected: (_) => setState(() {
              _filter = null;
              _buffetOnly = false;
            }),
          ),
          for (final k in ExpenseKind.values) ...[
            const SizedBox(width: Dimensions.spaceXS),
            ChoiceChip(
              avatar: Icon(k.icon, size: 18),
              label: Text(k.label),
              selected: _filter == k,
              onSelected: (_) => setState(() {
                _filter = k;
                _buffetOnly = false;
              }),
            ),
            if (k == ExpenseKind.supplies) ...[
              const SizedBox(width: Dimensions.spaceXS),
              ChoiceChip(
                avatar: const Icon(_buffetIcon, size: 18),
                label: const Text('مشتريات البوفيه'),
                selected: _buffetOnly,
                onSelected: (_) => setState(() {
                  _filter = null;
                  _buffetOnly = true;
                }),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ExpensesCubit>().state;
    // القائمة: المصاريف (حسب الفلتر) + دفعات مشتريات البوفيه (تظهر مع "الكل"
    // ومع فلتر المشتريات فقط)، الأحدث أولًا.
    final shown = <_Entry>[
      if (!_buffetOnly)
        for (final e in state.expenses)
          if (_filter == null || e.kind == _filter) _Entry.expense(e),
      if (_filter == null)
        for (final p in state.buffetPayments) _Entry.payment(p),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < Breakpoints.phone;

        final header = <Widget>[
          _toolbar(context, state, narrow),
          const SizedBox(height: Dimensions.spaceM),
          _summary(state),
          const SizedBox(height: Dimensions.spaceM),
          _filters(),
          const SizedBox(height: Dimensions.spaceM),
          if (_buffetOnly && !state.isLoading && state.buffetUnpaid.amount > 0) ...[
            _UnpaidNote(amount: state.buffetUnpaid),
            const SizedBox(height: Dimensions.spaceS),
          ],
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
            if (_buffetOnly) {
              return EmptyState(
                icon: _buffetIcon,
                title: 'لا توجد دفعات مشتريات في ${monthLabel(state.year, state.month)}',
                message:
                    'المشتريات تُسجَّل وتُسدَّد من صفحة المخزون والجرد، وتظهر هنا حسب تاريخ الدفع.',
              );
            }
            return EmptyState(
              icon: Icons.account_balance_wallet_rounded,
              title: 'لا توجد مصاريف في ${monthLabel(state.year, state.month)}',
              message: _filter == null
                  ? 'اضغط "إضافة مصروف" لتسجيل صيانة أو رواتب أو مستلزمات أو مسحوبات أو احتياطي.'
                  : 'لا توجد مصاريف من نوع "${_filter!.label}" في هذا الشهر.',
            );
          }
          final entry = shown[i - header.length];
          final e = entry.expense;
          return Padding(
            padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
            child: e != null
                ? _ExpenseCard(
                    expense: e,
                    onEdit: () => showExpenseFormDialog(context, existing: e),
                    onDelete: () => _delete(e),
                  )
                : _BuffetPaymentCard(
                    payment: entry.payment!,
                    // مع "الكل" نترك مكان أزرار التعديل فارغًا ليصطف المبلغ مع
                    // مبالغ المصاريف؛ وفي عرض المشتريات وحدها يلتصق المبلغ بالحافة.
                    alignWithActions: !_buffetOnly,
                  ),
          );
        }

        final itemCount =
            header.length + (state.isLoading || shown.isEmpty ? 1 : shown.length);

        return ListView.builder(
          padding: _pagePadding(c.maxWidth),
          itemCount: itemCount,
          itemBuilder: (context, i) => body(i),
        );
      },
    );
  }
}

/// سطر في القائمة: مصروف مسجَّل أو دفعة مشتريات بوفيه (عرض فقط).
class _Entry {
  final Expense? expense;
  final BuffetPayment? payment;
  const _Entry.expense(Expense this.expense) : payment = null;
  const _Entry.payment(BuffetPayment this.payment) : expense = null;

  DateTime get date => expense?.date ?? payment!.paidAt;
}

/// سطر معلومات في عرض مشتريات البوفيه: ما بقي غير مسدَّد للموردين حتى نهاية
/// الشهر (لا يدخل في إجمالي الشهر لأنه لم يُدفع بعد).
class _UnpaidNote extends StatelessWidget {
  final Money amount;
  const _UnpaidNote({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
        const SizedBox(width: Dimensions.spaceXS),
        Expanded(
          child: Text(
            'غير مسدَّد للموردين حتى نهاية الشهر: ${formatMoneyWithUnit(amount)} (لا يدخل في الإجمالي)',
            style: AppTextStyles.bodySmall(AppColors.warning),
          ),
        ),
      ],
    );
  }
}

/// منتقي الشهر: السابق على اليمين والتالي على اليسار (الواجهة عربية).
/// أيقونات chevron تنعكس تلقائيًا مع اتجاه النص، فنستعمل `left` للسابق.
class _MonthNavigator extends StatelessWidget {
  final String label;
  final bool expand;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  const _MonthNavigator({
    required this.label,
    required this.expand,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final title = Text(
      label,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.heading3(),
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'الشهر السابق',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          if (expand)
            Expanded(child: title)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 150),
              child: title,
            ),
          IconButton(
            tooltip: 'الشهر التالي',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool emphasized;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accentColor: emphasized ? color : null,
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceS, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Dimensions.spaceS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.bodySmall(AppColors.textSecondary),
                  ),
                ),
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

    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
      ),
      child: Icon(e.kind.icon, color: color, size: 22),
    );

    final info = Column(
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
    );

    final amount = Text(
      formatMoneyWithUnit(e.amount),
      style: AppTextStyles.price(color, 16),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'تعديل',
          visualDensity: VisualDensity.compact,
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded),
        ),
        IconButton(
          tooltip: 'حذف',
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        ),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          // ضيق: سطر للمعلومات وسطر تحته للمبلغ والأزرار.
          if (c.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: Dimensions.spaceS),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: amount,
                      ),
                    ),
                    actions,
                  ],
                ),
              ],
            );
          }
          // عريض: المبلغ بعمود ثابت العرض ليصطف مع بقية الأسطر.
          return Row(
            children: [
              icon,
              const SizedBox(width: Dimensions.spaceS),
              Expanded(child: info),
              const SizedBox(width: Dimensions.spaceS),
              SizedBox(
                width: 150,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: amount,
                ),
              ),
              const SizedBox(width: Dimensions.spaceXS),
              actions,
            ],
          );
        },
      ),
    );
  }
}

/// دفعة مشتريات بوفيه: بلا أزرار تعديل ولا حذف. تُدار من صفحة المخزون
/// والجرد (فواتير المشتريات).
class _BuffetPaymentCard extends StatelessWidget {
  final BuffetPayment payment;

  /// true: يُترك عرض أزرار التعديل/الحذف فارغًا ليصطف المبلغ مع بطاقات المصاريف.
  final bool alignWithActions;
  const _BuffetPaymentCard({
    required this.payment,
    this.alignWithActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final supplier = p.supplier?.trim() ?? '';
    final invoiceNo = p.invoiceNo?.trim() ?? '';
    final invoiceDay = formatDate(p.purchasedAt);
    final paidDay = formatDate(p.paidAt);

    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _buffetColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Dimensions.radiusM),
      ),
      child: const Icon(_buffetIcon, color: _buffetColor, size: 22),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          supplier.isEmpty ? 'دفعة مشتريات' : 'دفعة مشتريات — $supplier',
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
            const StatusBadge(
              label: 'مشتريات البوفيه',
              color: _buffetColor,
              icon: _buffetIcon,
            ),
            if (invoiceNo.isNotEmpty)
              Text('فاتورة رقم $invoiceNo',
                  style: AppTextStyles.bodySmall(AppColors.textSecondary)),
            Text('${arabicDayName(p.paidAt)}  $paidDay',
                style: AppTextStyles.bodySmall(AppColors.textSecondary)),
            if (invoiceDay != paidDay)
              Text('تاريخ الفاتورة: $invoiceDay',
                  style: AppTextStyles.bodySmall(AppColors.textMuted)),
          ],
        ),
      ],
    );

    final amount = Text(
      formatMoneyWithUnit(p.amount),
      style: AppTextStyles.price(_buffetColor, 16),
    );

    // مكان أزرار التعديل/الحذف عند المصاريف: فراغ بنفس العرض ليصطف المبلغ.
    const actionsGap = SizedBox(width: Dimensions.spaceXS + 80);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Dimensions.spaceM, vertical: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: Dimensions.spaceS),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: amount,
                ),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: Dimensions.spaceS),
              Expanded(child: info),
              const SizedBox(width: Dimensions.spaceS),
              SizedBox(
                width: 150,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: amount,
                ),
              ),
              if (alignWithActions) actionsGap,
            ],
          );
        },
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
    return LayoutBuilder(
      builder: (context, c) => ListView.builder(
        padding: _pagePadding(c.maxWidth),
        itemCount: list.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: Dimensions.spaceS),
          child: _LogCard(entry: list[i]),
        ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الشارات تلتف على سطر ثانٍ عند الضيق بدل أن تتجاوز العرض.
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    StatusBadge(
                        label: entry.action.label, color: _actionColor, icon: _actionIcon),
                    StatusBadge(label: kind.label, color: _kindColor(kind), icon: kind.icon),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
