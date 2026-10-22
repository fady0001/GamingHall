import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/app_dialog.dart';
import '../../../../core/widgets/friendly_error.dart';
import '../../domain/entities/resource_type.dart';
import '../cubit/resources_cubit.dart';

/// إضافة نوع طاولة جديد، أو تعديل اسم نوع موجود ([existing]).
/// يعيد true عند الحفظ.
Future<bool> showTableTypeDialog(BuildContext context, {ResourceType? existing}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _TableTypeDialog(existing: existing),
  );
  return ok ?? false;
}

class _TableTypeDialog extends StatefulWidget {
  final ResourceType? existing;
  const _TableTypeDialog({this.existing});

  @override
  State<_TableTypeDialog> createState() => _TableTypeDialogState();
}

class _TableTypeDialogState extends State<_TableTypeDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسم النوع');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final cubit = context.read<ResourcesCubit>();
    try {
      if (_isEdit) {
        await cubit.renameType(widget.existing!.id, name);
      } else {
        await cubit.addType(name);
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
    return AppDialog(
      title: _isEdit ? 'تعديل نوع الطاولة' : 'إضافة نوع طاولة',
      icon: Icons.table_restaurant_rounded,
      width: 460,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(_isEdit ? 'حفظ' : 'إضافة'),
        ),
      ],
      child: TextField(
        controller: _name,
        autofocus: true,
        enabled: !_busy,
        maxLength: 40,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'اسم النوع (مثال: بلياردو)',
          errorText: _error,
          counterText: '',
        ),
      ),
    );
  }
}
