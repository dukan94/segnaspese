import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/budget_providers.dart';
import '../../../core/utils/app_snackbar.dart';

/// Analizza un importo scritto dall'utente in formato italiano.
/// Se contiene una virgola la tratta come separatore decimale (e i punti come
/// migliaia); altrimenti usa il punto come decimale.
double? parseItalianAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  final value = double.tryParse(s);
  if (value == null || value < 0) return null;
  return value;
}

/// Dialog per impostare/modificare un importo di budget: il totale di un mese
/// ([categoryId] null) o l'allocazione di una categoria ([categoryId]
/// valorizzato). Se [existingId] è presente mostra anche "Rimuovi".
Future<void> showBudgetAmountDialog(
  BuildContext context, {
  required MonthKey month,
  int? categoryId,
  required String title,
  String? subtitle,
  double? initialAmount,
  int? existingId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BudgetAmountDialog(
      month: month,
      categoryId: categoryId,
      title: title,
      subtitle: subtitle,
      initialAmount: initialAmount,
      existingId: existingId,
    ),
  );
}

class _BudgetAmountDialog extends ConsumerStatefulWidget {
  const _BudgetAmountDialog({
    required this.month,
    required this.categoryId,
    required this.title,
    required this.subtitle,
    required this.initialAmount,
    required this.existingId,
  });

  final MonthKey month;
  final int? categoryId;
  final String title;
  final String? subtitle;
  final double? initialAmount;
  final int? existingId;

  @override
  ConsumerState<_BudgetAmountDialog> createState() =>
      _BudgetAmountDialogState();
}

class _BudgetAmountDialogState extends ConsumerState<_BudgetAmountDialog> {
  late final _controller = TextEditingController(
    text: widget.initialAmount == null
        ? ''
        : widget.initialAmount!
            .toStringAsFixed(2)
            .replaceAll('.', ','),
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseItalianAmount(_controller.text);
    if (amount == null) {
      showErrorSnackBar(context, 'Inserisci un importo valido');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.categoryId == null) {
        await ref
            .read(setMonthlyBudgetProvider)
            .call(month: widget.month.firstDay, amount: amount);
      } else {
        await ref.read(setCategoryBudgetProvider).call(
              categoryId: widget.categoryId!,
              month: widget.month.firstDay,
              amount: amount,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore: $e');
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await ref.read(deleteBudgetProvider).call(widget.existingId!);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Importo',
              suffixText: '€',
              hintText: 'Es. 400,00',
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
        ],
      ),
      actions: [
        if (widget.existingId != null)
          TextButton(
            onPressed: _saving ? null : _remove,
            child: Text(
              'Rimuovi',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salva'),
        ),
      ],
    );
  }
}
