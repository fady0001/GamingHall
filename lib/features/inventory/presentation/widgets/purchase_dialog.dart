// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';

// import '../../../../core/domain/value_objects/money.dart';
// import '../../../../core/domain/value_objects/money_parser.dart';
// import '../../../../core/theme/app_colors.dart';
// import '../../../../core/theme/dimensions.dart';
// import '../../../../core/theme/text_styles.dart';
// import '../../../../core/utils/number_format.dart';
// import '../../../../core/utils/time_format.dart';
// import '../../../../core/widgets/app_dialog.dart';
// import '../../../../core/widgets/friendly_error.dart';
// import '../../../../core/widgets/money_field.dart';
// import '../../domain/entities/inventory_models.dart';
// import '../cubit/inventory_cubit.dart';

// /// حقل عدد صحيح (أرقام فقط، اتجاه لاتيني).
// class IntField extends StatelessWidget {
//   final TextEditingController controller;
//   final String label;
//   final IconData icon;
//   final String? errorText;
//   final bool enabled;
//   final ValueChanged<String>? onChanged;

//   const IntField({
//     super.key,
//     required this.controller,
//     required this.label,
//     required this.icon,
//     this.errorText,
//     this.enabled = true,
//     this.onChanged,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return TextField(
//       controller: controller,
//       enabled: enabled,
//       textDirection: TextDirection.ltr,
//       textAlign: TextAlign.start,
//       keyboardType: TextInputType.number,
//       inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]'))],
//       onChanged: onChanged,
//       decoration: InputDecoration(
//         labelText: label,
//         errorText: errorText,
//         prefixIcon: Icon(icon),
//       ),
//     );
//   }
// }

// /// يقرأ عددًا صحيحًا من نص المستخدم (يقبل الأرقام العربية). null إن كان فارغًا.
// int? parseIntField(String text) {
//   final digits = toLatinDigits(text).replaceAll(RegExp(r'[^0-9]'), '');
//   if (digits.isEmpty || digits.length > 9) return null;
//   return int.tryParse(digits);
// }

// Future<bool> showPurchaseDialog(BuildContext context, List<StockRow> rows) async {
//   final ok = await showDialog<bool>(
//     context: context,
//     builder: (_) => _PurchaseDialog(rows: rows),
//   );
//   return ok ?? false;
// }

// class _PurchaseDialog extends StatefulWidget {
//   final List<StockRow> rows;
//   const _PurchaseDialog({required this.rows});

//   @override
//   State<_PurchaseDialog> createState() => _PurchaseDialogState();
// }

// class _PurchaseDialogState extends State<_PurchaseDialog> {
//   final _packs = TextEditingController();
//   final _pieces = TextEditingController();
//   final _packPrice = TextEditingController();
//   final _note = TextEditingController();
//   int? _itemId;
//   late DateTime _date;
//   String? _itemError;
//   String? _packsError;
//   String? _piecesError;
//   String? _priceError;
//   String? _error;
//   bool _busy = false;

//   @override
//   void initState() {
//     super.initState();
//     _date = DateTime.now();
//   }

//   @override
//   void dispose() {
//     _packs.dispose();
//     _pieces.dispose();
//     _packPrice.dispose();
//     _note.dispose();
//     super.dispose();
//   }

//   Future<void> _pickDate() async {
//     final now = DateTime.now();
//     final picked = await showDatePicker(
//       context: context,
//       initialDate: _date,
//       firstDate: DateTime(now.year - 2),
//       lastDate: now,
//     );
//     if (picked == null) return;
//     // نحتفظ بالساعة الحالية حتى يبقى ترتيب المشتريات في اليوم الواحد منطقيًا.
//     setState(() => _date = DateTime(
//         picked.year, picked.month, picked.day, now.hour, now.minute));
//   }

//   Future<void> _submit() async {
//     final packs = parseIntField(_packs.text);
//     final pieces = parseIntField(_pieces.text);
//     final price = parseMoney(_packPrice.text);
//     setState(() {
//       _error = null;
//       _itemError = _itemId == null ? 'اختر الصنف' : null;
//       _packsError = (packs == null || packs <= 0) ? 'أدخل عدد الطرود' : null;
//       _piecesError = (pieces == null || pieces <= 0) ? 'أدخل عدد القطع' : null;
//       _priceError = (price == null || price.amount <= 0) ? 'أدخل سعر الطرد' : null;
//     });
//     if (_itemError != null ||
//         _packsError != null ||
//         _piecesError != null ||
//         _priceError != null) {
//       return;
//     }

//     setState(() => _busy = true);
//     try {
//       await context.read<InventoryCubit>().addPurchase(
//             itemId: _itemId!,
//             packs: packs!,
//             piecesPerPack: pieces!,
//             packPrice: price!,
//             purchasedAt: _date,
//             note: _note.text,
//           );
//       if (mounted) Navigator.of(context).pop(true);
//     } catch (e) {
//       if (mounted) {
//         setState(() {
//           _busy = false;
//           _error = friendlyError(e);
//         });
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final packs = parseIntField(_packs.text) ?? 0;
//     final pieces = parseIntField(_pieces.text) ?? 0;
//     final price = parseMoney(_packPrice.text)?.amount ?? 0;
//     final ready = packs > 0 && pieces > 0 && price > 0;

//     return AppDialog(
//       title: 'تسجيل شراء بوفيه',
//       icon: Icons.shopping_cart_checkout_rounded,
//       iconColor: AppColors.secondary,
//       width: 520,
//       actions: [
//         TextButton(
//           onPressed: _busy ? null : () => Navigator.of(context).pop(false),
//           child: const Text('إلغاء'),
//         ),
//         FilledButton.icon(
//           onPressed: _busy ? null : _submit,
//           icon: const Icon(Icons.check_rounded),
//           label: const Text('حفظ الشراء'),
//         ),
//       ],
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           DropdownButtonFormField<int>(
//             initialValue: _itemId,
//             isExpanded: true,
//             decoration: InputDecoration(
//               labelText: 'الصنف',
//               prefixIcon: const Icon(Icons.label_rounded),
//               errorText: _itemError,
//             ),
//             items: [
//               for (final r in widget.rows)
//                 DropdownMenuItem<int>(
//                   value: r.itemId,
//                   child: Text(r.name, overflow: TextOverflow.ellipsis),
//                 ),
//             ],
//             onChanged: _busy ? null : (v) => setState(() => _itemId = v),
//           ),
//           const SizedBox(height: Dimensions.spaceM),
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(
//                 child: IntField(
//                   controller: _packs,
//                   label: 'عدد الطرود',
//                   icon: Icons.inventory_2_rounded,
//                   errorText: _packsError,
//                   enabled: !_busy,
//                   onChanged: (_) => setState(() {}),
//                 ),
//               ),
//               const SizedBox(width: Dimensions.spaceS),
//               Expanded(
//                 child: IntField(
//                   controller: _pieces,
//                   label: 'عدد القطع بالطرد',
//                   icon: Icons.apps_rounded,
//                   errorText: _piecesError,
//                   enabled: !_busy,
//                   onChanged: (_) => setState(() {}),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: Dimensions.spaceM),
//           MoneyField(
//             controller: _packPrice,
//             label: 'سعر الطرد',
//             errorText: _priceError,
//             enabled: !_busy,
//             onChanged: (_) => setState(() {}),
//           ),
//           const SizedBox(height: Dimensions.spaceM),
//           Container(
//             padding: const EdgeInsets.all(Dimensions.spaceM),
//             decoration: BoxDecoration(
//               color: AppColors.surfaceHigh,
//               borderRadius: BorderRadius.circular(Dimensions.radiusM),
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 _line('إجمالي القطع', ready ? '${groupThousands(packs * pieces)} قطعة' : '—'),
//                 const SizedBox(height: 6),
//                 _line(
//                   'سعر القطعة (سعر الطرد ÷ القطع)',
//                   ready ? formatMoneyWithUnit(Money(unitCostFor(price, pieces))) : '—',
//                 ),
//                 const SizedBox(height: 6),
//                 _line(
//                   'إجمالي المبلغ',
//                   ready ? formatMoneyWithUnit(Money(packs * price)) : '—',
//                   bold: true,
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: Dimensions.spaceM),
//           OutlinedButton.icon(
//             onPressed: _busy ? null : _pickDate,
//             icon: const Icon(Icons.event_rounded),
//             label: Text('تاريخ الشراء: ${formatDate(_date)}'),
//           ),
//           const SizedBox(height: Dimensions.spaceM),
//           TextField(
//             controller: _note,
//             enabled: !_busy,
//             maxLength: 120,
//             decoration: const InputDecoration(
//               labelText: 'ملاحظة (اختياري)',
//               prefixIcon: Icon(Icons.notes_rounded),
//               counterText: '',
//             ),
//           ),
//           if (_error != null) ...[
//             const SizedBox(height: Dimensions.spaceM),
//             Text(_error!, style: AppTextStyles.bodyMedium(AppColors.danger)),
//           ],
//         ],
//       ),
//     );
//   }

//   Widget _line(String label, String value, {bool bold = false}) => Row(
//         children: [
//           Expanded(child: Text(label, style: AppTextStyles.bodyMedium(AppColors.textSecondary))),
//           Text(
//             value,
//             style: bold
//                 ? AppTextStyles.price(AppColors.secondary, 16)
//                 : AppTextStyles.bodyLarge(),
//           ),
//         ],
//       );
// }
