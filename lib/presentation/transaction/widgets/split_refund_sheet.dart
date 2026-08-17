import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/transaction_providers.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../../domain/usecases/transaction/build_split_refund.dart';

/// Bottom sheet "Rimborso con divisore" (M25): da una spesa esistente, crea
/// un rimborso pari a 1/N dell'importo con una nota facoltativa (di solito
/// chi restituisce la quota) — senza passare dal form completo di "Nuova
/// Operazione". Categoria e sottocategoria ereditate, non modificabili: a
/// differenza del rimborso manuale (`AddTransactionPage(refundOf: ...)`),
/// qui la scelta è deliberatamente rapida, non flessibile.
Future<void> showSplitRefundSheet(
  BuildContext context,
  TransactionEntity expense,
  Category? category,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) =>
        _SplitRefundSheetContent(expense: expense, category: category),
  );
}

class _SplitRefundSheetContent extends ConsumerStatefulWidget {
  const _SplitRefundSheetContent({required this.expense, this.category});

  final TransactionEntity expense;
  final Category? category;

  @override
  ConsumerState<_SplitRefundSheetContent> createState() =>
      _SplitRefundSheetContentState();
}

class _SplitRefundSheetContentState
    extends ConsumerState<_SplitRefundSheetContent> {
  static const _buildSplitRefund = BuildSplitRefund();

  final _divisorController = TextEditingController();
  late final _noteController =
      TextEditingController(text: widget.expense.note ?? '');
  String? _divisorError;
  bool _saving = false;

  int? get _divisor => int.tryParse(_divisorController.text);

  double? get _quota {
    final divisor = _divisor;
    if (divisor == null || divisor < 2) return null;
    return (widget.expense.amount / divisor * 100).round() / 100;
  }

  @override
  void dispose() {
    _divisorController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final divisor = _divisor;
    if (divisor == null || divisor < 2) {
      setState(() => _divisorError = 'Inserisci un numero intero di almeno 2');
      return;
    }
    setState(() {
      _divisorError = null;
      _saving = true;
    });
    try {
      final refund = _buildSplitRefund(
        expense: widget.expense,
        divisor: divisor,
        today: DateTime.now(),
        note: _noteController.text,
      );
      await ref.read(addTransactionProvider)(refund);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        'Rimborso di ${AppFormatters.currency(refund.amount)} creato',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expense = widget.expense;
    final catName = widget.category?.name ?? 'Senza categoria';
    final quota = _quota;

    return Padding(
      // Solleva il contenuto sopra la tastiera a schermo intero (mobile).
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.call_split, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Rimborso con divisore', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text(widget.category?.icon ?? '💶',
                      style: const TextStyle(fontSize: 18)),
                ),
                title: Text(
                    expense.note?.isNotEmpty == true ? expense.note! : catName),
                subtitle:
                    Text('$catName · ${AppFormatters.shortDate(expense.date)}'),
                trailing: Text(
                  AppFormatters.currency(expense.amount),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _divisorController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Divisore',
                  hintText: 'In quante parti dividere (almeno 2)',
                  errorText: _divisorError,
                ),
                onChanged: (_) {
                  if (_divisorError != null) setState(() => _divisorError = null);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (facoltativo)',
                  hintText: 'Es. il nome di chi restituisce la quota',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                quota == null ? 'Quota: —' : 'Quota: ${AppFormatters.currency(quota)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: quota == null ? theme.colorScheme.outline : null,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crea rimborso'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
