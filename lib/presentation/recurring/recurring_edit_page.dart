import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/recurring_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/recurring_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../transaction/widgets/category_picker.dart';

/// Schermata di creazione/modifica di un movimento ricorrente.
///
/// Se [existing] è valorizzata, modifica quella ricorrenza; altrimenti ne crea
/// una nuova. La sottocategoria è obbligatoria (la categoria è derivata da
/// essa), coerentemente con la schermata "Nuova Operazione".
class RecurringEditPage extends ConsumerStatefulWidget {
  const RecurringEditPage({super.key, this.existing});

  final RecurringEntity? existing;

  @override
  ConsumerState<RecurringEditPage> createState() => _RecurringEditPageState();
}

class _RecurringEditPageState extends ConsumerState<RecurringEditPage> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _dayOfMonthController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  SubCategorySelection? _selection;
  RecurringFrequencyType _frequency = RecurringFrequencyType.monthly;
  DateTime _nextOccurrence = DateTime.now();
  bool _active = true;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _frequency = e.frequency;
      _nextOccurrence = e.nextOccurrence;
      _active = e.active;
      _descriptionController.text = e.description;
      _amountController.text = _formatAmountForEditing(e.amount);
      if (e.dayOfMonth != null) {
        _dayOfMonthController.text = '${e.dayOfMonth}';
      }
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
    _descriptionController.dispose();
    _amountController.dispose();
    _dayOfMonthController.dispose();
    super.dispose();
  }

  static String _formatAmountForEditing(double amount) {
    // Mostra senza decimali inutili (es. 12 anziché 12.0), con la virgola
    // decimale italiana.
    final s = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toString();
    return s.replaceAll('.', ',');
  }

  /// Parsing tollerante dell'importo digitato (accetta "12,99", "12.99" e
  /// separatori delle migliaia "1.234,56").
  static double? _parseAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(s);
  }

  bool get _canSave =>
      !_saving &&
      _selection != null &&
      _descriptionController.text.trim().isNotEmpty &&
      (_parseAmount(_amountController.text) ?? 0) > 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextOccurrence,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _nextOccurrence = picked);
    }
  }

  Future<void> _save() async {
    final amount = _parseAmount(_amountController.text);
    final selection = _selection;
    if (amount == null || amount <= 0 || selection == null) return;

    setState(() => _saving = true);

    int? dayOfMonth;
    if (_frequency == RecurringFrequencyType.monthly) {
      final parsed = int.tryParse(_dayOfMonthController.text.trim());
      if (parsed != null && parsed >= 1 && parsed <= 31) {
        dayOfMonth = parsed;
      }
    }

    // Normalizza la data a mezzanotte: conta solo il giorno.
    final next = DateTime(
      _nextOccurrence.year,
      _nextOccurrence.month,
      _nextOccurrence.day,
    );

    final entity = RecurringEntity(
      id: widget.existing?.id,
      description: _descriptionController.text.trim(),
      amount: amount,
      type: _type,
      categoryId: selection.categoryId,
      subCategoryId: selection.subCategoryId,
      frequency: _frequency,
      dayOfMonth: dayOfMonth,
      nextOccurrence: next,
      active: _active,
    );

    try {
      if (_isEditing) {
        await ref.read(updateRecurringProvider).call(entity);
      } else {
        await ref.read(addRecurringProvider).call(entity);
      }
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        _isEditing ? 'Ricorrenza aggiornata' : 'Ricorrenza salvata',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore nel salvataggio: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica ricorrenza' : 'Nuova ricorrenza'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Salva'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tipo movimento
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(
                value: TransactionType.expense,
                label: Text('Uscita'),
                icon: Icon(Icons.south_west),
              ),
              ButtonSegment(
                value: TransactionType.income,
                label: Text('Entrata'),
                icon: Icon(Icons.north_east),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() {
                _type = s.first;
                // La sottocategoria dipende dal tipo: va riscelta.
                _selection = null;
              });
            },
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Descrizione',
              hintText: 'Es. Netflix, Stipendio, Affitto',
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Importo',
              suffixText: '€',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          SubCategoryPicker(
            type: _type,
            selection: _selection,
            onChanged: (s) => setState(() => _selection = s),
          ),
          const SizedBox(height: 16),

          // Frequenza
          DropdownButtonFormField<RecurringFrequencyType>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Frequenza'),
            items: const [
              DropdownMenuItem(
                value: RecurringFrequencyType.weekly,
                child: Text('Settimanale'),
              ),
              DropdownMenuItem(
                value: RecurringFrequencyType.monthly,
                child: Text('Mensile'),
              ),
              DropdownMenuItem(
                value: RecurringFrequencyType.yearly,
                child: Text('Annuale'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _frequency = value);
            },
          ),
          const SizedBox(height: 16),

          // Giorno del mese (solo mensile, opzionale)
          if (_frequency == RecurringFrequencyType.monthly) ...[
            TextField(
              controller: _dayOfMonthController,
              decoration: const InputDecoration(
                labelText: 'Giorno del mese (opzionale)',
                hintText: 'Es. 1, 15, 27 — vuoto: usa il giorno qui sotto',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Prossima occorrenza
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _isEditing
                    ? 'Prossima occorrenza'
                    : 'Prima occorrenza',
              ),
              child: Row(
                children: [
                  Expanded(child: Text(AppFormatters.shortDate(_nextOccurrence))),
                  const Icon(Icons.calendar_today_outlined, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          if (_isEditing)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Attiva'),
              subtitle: const Text(
                'Se disattivata non genera nuove transazioni',
              ),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
        ],
      ),
    );
  }
}
