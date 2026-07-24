import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/transaction_entity.dart';
import 'widgets/amount_keypad.dart';
import 'widgets/category_picker.dart';

/// Schermata "Nuova Operazione" (inserimento manuale), v. wireframe
/// progettazione. Obiettivo: 3-4 tap per salvare un movimento.
///
/// Il campo "Negozio" del wireframe originale richiede il modulo Merchant
/// (Milestone M3/M6): per ora l'utente può comunque annotare il negozio nel
/// campo Note.
class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({super.key, this.existing});

  /// Se valorizzata, la schermata modifica questa operazione invece di crearne
  /// una nuova.
  final TransactionEntity? existing;

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  TransactionType _type = TransactionType.expense;
  double _amount = 0;
  SubCategorySelection? _selection;
  DateTime _date = DateTime.now();
  final _noteController = TextEditingController();
  bool _isExtraordinary = false;
  bool _isRefund = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _amount = e.amount;
      _date = e.date;
      _isExtraordinary = e.isExtraordinary;
      _isRefund = e.isRefund;
      _noteController.text = e.note ?? '';
      if (e.subCategoryId != null) {
        _selection = SubCategorySelection(
          categoryId: e.categoryId,
          subCategoryId: e.subCategoryId!,
        );
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // La sottocategoria è obbligatoria: la categoria viene derivata da essa,
  // non si seleziona più separatamente.
  bool get _canSave => _amount > 0 && _selection != null && !_saving;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    final entity = TransactionEntity(
      id: widget.existing?.id,
      date: _date,
      amount: _amount,
      type: _type,
      categoryId: _selection!.categoryId,
      subCategoryId: _selection!.subCategoryId,
      note: note,
      isExtraordinary: _isExtraordinary,
      isRefund: _isRefund,
      merchantId: widget.existing?.merchantId,
      receiptImagePath: widget.existing?.receiptImagePath,
      recurringId: widget.existing?.recurringId,
    );

    try {
      if (_isEditing) {
        await ref.read(updateTransactionProvider).call(entity);
      } else {
        await ref.read(addTransactionProvider).call(entity);
      }
      if (!mounted) return;
      showSuccessSnackBar(
          context, _isEditing ? 'Operazione aggiornata' : 'Operazione salvata');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore durante il salvataggio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEditing ? 'Modifica operazione' : 'Nuova operazione'),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _canSave ? _save : null,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            AmountKeypad(
              initialAmount: widget.existing?.amount,
              onChanged: (value) => setState(() => _amount = value),
            ),
            const SizedBox(height: 20),
            if (!_isRefund)
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.income,
                    label: Text('Entrata'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Uscita'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() {
                    _type = selection.first;
                    // Le sottocategorie disponibili dipendono dal tipo: reset.
                    _selection = null;
                  });
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isRefund,
              onChanged: (v) => setState(() {
                _isRefund = v;
                // Un rimborso è sempre relativo a una spesa: forza il tipo a
                // uscita e azzera la scelta, così il picker mostra le spese.
                if (v) _type = TransactionType.expense;
                _selection = null;
              }),
              title: const Text('Rimborso ricevuto'),
              subtitle: const Text('Riduce la spesa della categoria scelta'),
            ),
            const SizedBox(height: 12),
            SubCategoryPicker(
              key: ValueKey('$_type-$_isRefund'),
              type: _type,
              selection: _selection,
              onChanged: (value) => setState(() => _selection = value),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Data'),
              trailing: Text(AppFormatters.shortDate(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (opzionale)',
                hintText: 'Es. negozio, dettagli...',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isExtraordinary,
              onChanged: (v) => setState(() => _isExtraordinary = v),
              title: const Text('Straordinaria'),
              subtitle: const Text(
                  'Operazione una tantum, esclusa di default dalle statistiche'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Salva'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
