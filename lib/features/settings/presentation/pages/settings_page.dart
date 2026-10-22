import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_info.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/money_parser.dart';
import '../../../../core/security/hardware_fingerprint_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/widgets/adaptive.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../../../core/widgets/money_field.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/section_title.dart';
import '../../../../core/widgets/snackbars.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../printing/data/invoice_printer.dart';
import '../../domain/entities/app_settings.dart';
import '../cubit/settings_cubit.dart';
import '../widgets/backup_section.dart';
import '../widgets/change_password_dialog.dart';

/// الإعدادات (للمدير فقط).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _lounge = TextEditingController();
  final _phone = TextEditingController();
  final _footer = TextEditingController();
  final _minimum = TextEditingController();

  int _rounding = 1;
  int _reminder = 15;
  bool _autoPrint = false;
  String _printer = '';
  List<String> _printers = const [];
  bool _printersLoading = false;
  bool _saving = false;
  String? _minimumError;
  String? _loungeError;

  String? _username;
  String? _deviceCode;

  @override
  void initState() {
    super.initState();
    _load(context.read<SettingsCubit>().state.settings);
    _loadPrinters();
    context.read<AuthCubit>().managerUsername().then((u) {
      if (mounted) setState(() => _username = u);
    });
    HardwareFingerprintService.computeFingerprint().then((c) {
      if (mounted) setState(() => _deviceCode = c);
    }).catchError((_) {
      if (mounted) setState(() => _deviceCode = '—');
    });
  }

  void _load(AppSettings s) {
    _lounge.text = s.loungeName;
    _phone.text = s.loungePhone;
    _footer.text = s.invoiceFooter;
    _minimum.text = formatMoney(s.minimumInvoice);
    _rounding = s.roundingStep;
    _reminder = s.reminderIntervalMinutes;
    _autoPrint = s.autoPrint;
    _printer = s.printerName;
  }

  Future<void> _loadPrinters() async {
    setState(() => _printersLoading = true);
    final names = await InvoicePrinter.printerNames();
    if (mounted) setState(() {
      _printers = names;
      _printersLoading = false;
    });
  }

  @override
  void dispose() {
    _lounge.dispose();
    _phone.dispose();
    _footer.dispose();
    _minimum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minimum = parseMoney(_minimum.text);
    setState(() {
      _loungeError = _lounge.text.trim().isEmpty ? 'اسم الصالة مطلوب' : null;
      _minimumError = minimum == null ? 'أدخل مبلغًا (يمكن أن يكون 0)' : null;
    });
    if (_loungeError != null || _minimumError != null) return;

    setState(() => _saving = true);
    final cubit = context.read<SettingsCubit>();
    try {
      await cubit.save(cubit.state.settings.copyWith(
        loungeName: _lounge.text.trim(),
        loungePhone: _phone.text.trim(),
        invoiceFooter: _footer.text.trim(),
        minimumInvoice: minimum ?? const Money(0),
        roundingStep: _rounding,
        reminderIntervalMinutes: _reminder,
        autoPrint: _autoPrint,
        printerName: _printer,
      ));
      if (mounted) showAppSnack(context, 'تم حفظ الإعدادات');
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final ok = await showChangePasswordDialog(context);
    if (ok && mounted) showAppSnack(context, 'تم تغيير كلمة السر');
  }

  @override
  Widget build(BuildContext context) {
    final printerItems = <String>{..._printers, if (_printer.isNotEmpty) _printer}.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'الإعدادات',
          subtitle: 'بيانات الصالة والتسعير والتنبيهات والطباعة والأمان',
          actions: [
            SizedBox(
              height: Dimensions.buttonHeightLarge,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('حفظ الإعدادات'),
              ),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                context.isPhone ? Dimensions.spaceM : Dimensions.spaceL,
                0,
                context.isPhone ? Dimensions.spaceM : Dimensions.spaceL,
                Dimensions.spaceXL),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card('بيانات الصالة والفاتورة', Icons.storefront_rounded, [
                      TextField(
                        controller: _lounge,
                        maxLength: 40,
                        decoration: InputDecoration(
                          labelText: 'اسم الصالة (يظهر على الفاتورة)',
                          prefixIcon: const Icon(Icons.storefront_rounded),
                          errorText: _loungeError,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: Dimensions.spaceM),
                      TextField(
                        controller: _phone,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'رقم هاتف الصالة (اختياري)',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                      ),
                      const SizedBox(height: Dimensions.spaceM),
                      TextField(
                        controller: _footer,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'عبارة أسفل الفاتورة',
                          prefixIcon: Icon(Icons.short_text_rounded),
                          counterText: '',
                        ),
                      ),
                    ]),
                    _card('التسعير', Icons.payments_rounded, [
                      MoneyField(
                        controller: _minimum,
                        label: 'أقل مبلغ للفاتورة',
                        errorText: _minimumError,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'أي فاتورة (فيها لعب أو طلبات) مجموعها أقل من هذا المبلغ تُحاسَب به. اكتب 0 لإلغاء الحد الأدنى.',
                        style: AppTextStyles.bodySmall(),
                      ),
                      const SizedBox(height: Dimensions.spaceM),
                      DropdownButtonFormField<int>(
                        initialValue: const [1, 100, 500, 1000].contains(_rounding) ? _rounding : 1,
                        decoration: const InputDecoration(
                          labelText: 'تقريب المبلغ النهائي',
                          prefixIcon: Icon(Icons.calculate_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('بدون تقريب')),
                          DropdownMenuItem(value: 100, child: Text('لأقرب 100 ل.س')),
                          DropdownMenuItem(value: 500, child: Text('لأقرب 500 ل.س')),
                          DropdownMenuItem(value: 1000, child: Text('لأقرب 1,000 ل.س')),
                        ],
                        onChanged: (v) => setState(() => _rounding = v ?? 1),
                      ),
                      const SizedBox(height: 6),
                      Text('وقت اللعب نفسه يُحسب دائمًا لأقرب دقيقة.',
                          style: AppTextStyles.bodySmall()),
                    ]),
                    _card('التنبيهات', Icons.notifications_active_rounded, [
                      Text('تذكير الموظف باللعب المفتوح الجاري', style: AppTextStyles.bodyLarge()),
                      const SizedBox(height: 4),
                      Text(
                        'يظهر تنبيه مع نغمة كل فترة، حتى لا يُنسى زبون يلعب. لا يوقف اللعب ولا يغيّر الحساب.',
                        style: AppTextStyles.bodySmall(),
                      ),
                      const SizedBox(height: Dimensions.spaceS),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 15, label: _SegLabel('كل ربع ساعة')),
                          ButtonSegment(value: 30, label: _SegLabel('كل نصف ساعة')),
                          ButtonSegment(value: 60, label: _SegLabel('كل ساعة')),
                          ButtonSegment(value: 0, label: _SegLabel('إيقاف')),
                        ],
                        selected: {const [15, 30, 60].contains(_reminder) ? _reminder : 0},
                        onSelectionChanged: (s) => setState(() => _reminder = s.first),
                      ),
                    ]),
                    _card('الطباعة', Icons.print_rounded, [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              // isExpanded: يقص النص الطويل بنقاط بدل أن يتجاوز عرض الحقل.
                              isExpanded: true,
                              initialValue: printerItems.contains(_printer) ? _printer : '',
                              decoration: const InputDecoration(
                                labelText: 'طابعة الفواتير',
                                prefixIcon: Icon(Icons.print_rounded),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: '',
                                    child: Text('الطابعة الافتراضية في ويندوز',
                                        overflow: TextOverflow.ellipsis)),
                                for (final p in printerItems)
                                  DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) => setState(() => _printer = v ?? ''),
                            ),
                          ),
                          const SizedBox(width: Dimensions.spaceS),
                          IconButton.outlined(
                            tooltip: 'تحديث قائمة الطابعات',
                            onPressed: _printersLoading ? null : _loadPrinters,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                      if (!_printersLoading && _printers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'لم يُعثر على أي طابعة مثبّتة. ثبّت تعريف الطابعة في ويندوز أولًا، '
                            'ويمكنك حفظ الفاتورة كملف PDF في هذه الأثناء.',
                            style: AppTextStyles.bodySmall(AppColors.warning),
                          ),
                        ),
                      const SizedBox(height: Dimensions.spaceS),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autoPrint,
                        onChanged: (v) => setState(() => _autoPrint = v),
                        title: Text('طباعة الفاتورة تلقائيًا عند المحاسبة',
                            style: AppTextStyles.bodyLarge()),
                      ),
                      Text('مقاس الفاتورة: إيصال حراري بعرض 80 مم.', style: AppTextStyles.bodySmall()),
                    ]),
                    _card('الأمان', Icons.shield_rounded, [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(Icons.person_rounded, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text('حساب المدير: ', style: AppTextStyles.bodyLarge(AppColors.textSecondary)),
                          Text(_username ?? '...',
                              textDirection: TextDirection.ltr, style: AppTextStyles.bodyLarge()),
                        ],
                      ),
                      const SizedBox(height: Dimensions.spaceM),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          onPressed: _changePassword,
                          icon: const Icon(Icons.lock_reset_rounded),
                          label: const Text('تغيير كلمة السر'),
                        ),
                      ),
                    ]),
                    _card('النسخ الاحتياطي', Icons.backup_rounded, const [BackupSection()]),
                    _card('حول التطبيق', Icons.info_outline_rounded, [
                      Text('${AppInfo.englishName} — ${AppInfo.arabicName}  (الإصدار ${AppInfo.version})',
                          style: AppTextStyles.bodyLarge()),
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('كود هذا الجهاز: ', style: AppTextStyles.bodyMedium(AppColors.textSecondary)),
                          SelectableText(_deviceCode ?? '...',
                              textDirection: TextDirection.ltr,
                              style: AppTextStyles.price(AppColors.secondary, 15)),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    final isPhone = context.isPhone;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimensions.spaceM),
      child: AppCard(
        padding: EdgeInsets.all(isPhone ? Dimensions.spaceM : Dimensions.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(title: title, icon: icon),
            const SizedBox(height: Dimensions.spaceM),
            ...children,
          ],
        ),
      ),
    );
  }
}


/// نص خيار داخل SegmentedButton يتصغّر بدل أن يتجاوز العرض في النوافذ الضيقة.
class _SegLabel extends StatelessWidget {
  final String text;
  const _SegLabel(this.text);

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1),
      );
}
