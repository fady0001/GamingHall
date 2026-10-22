import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/text_styles.dart';
import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../domain/entities/invoice.dart';
import '../cubit/invoices_cubit.dart';

/// إنشاء فاتورة جديدة باسم زبون (أو باسم أحد المجموعة إن كانوا أصدقاء معًا).
Future<Invoice?> showNewInvoiceDialog(BuildContext context) {
  return showDialog<Invoice>(
    context: context,
    builder: (_) => const _NewInvoiceDialog(),
  );
}

class _NewInvoiceDialog extends StatefulWidget {
  const _NewInvoiceDialog();

  @override
  State<_NewInvoiceDialog> createState() => _NewInvoiceDialogState();
}

class _NewInvoiceDialogState extends State<_NewInvoiceDialog> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم الزبون');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invoice = await context.read<InvoicesCubit>().create(_name.text);
      if (mounted) Navigator.of(context).pop(invoice);
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
    return AppDialog(
      title: 'فاتورة جديدة',
      icon: Icons.receipt_long_rounded,
      width: 440,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('إنشاء الفاتورة'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'اكتب اسم الزبون. إن جاء مع أصدقائه فاستخدم اسم أحدهم، فكل ما '
            'يلعبونه ويشترونه معًا يُسجَّل في فاتورة واحدة.',
            style: AppTextStyles.bodyMedium(AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_busy,
            maxLength: 60,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'اسم الزبون',
              prefixIcon: const Icon(Icons.person_rounded),
              errorText: _error,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}
