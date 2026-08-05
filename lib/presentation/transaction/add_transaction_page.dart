import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/usecases/transaction/search_transactions.dart';
import '../home/home_providers.dart';
import '../shared_widgets/empty_state.dart';
import 'widgets/amount_keypad.dart';
import 'widgets/category_picker.dart';

/// Schermata "Nuova Operazione" (inserimento manuale), v. wireframe
/// progettazione. Obiettivo: 3-4 tap per salvare un movimento.
///
/// Il campo "Negozio" del wireframe originale richiede il modulo Merchant
/// (Milestone M3/M6): per ora l'utente può comunque annotare il negozio nel
/// campo Note.
class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({
    super.key,
    this.existing,
    this.refundOf,
    this.draftDate,
    this.draftAmount,
    this.draftType,
    this.draftNote,
    this.draftSelection,
    this.onDraftSaved,
  });

  /// Se valorizzata, la schermata modifica questa operazione invece di crearne
  /// una nuova.
  final TransactionEntity? existing;

  /// Se valorizzata, la schermata parte come RIMBORSO collegato a questa spesa:
  /// eredita categoria, sottocategoria e data (modificabili); l'utente inserisce
  /// solo l'importo. Usato dall'azione "Rimborsa" nello Storico.
  final TransactionEntity? refundOf;

  // --- Modifica "in bozza" (v. import estratto conto) ---
  //
  // Precompilano il form come [existing], ma senza semantica di
  // aggiornamento DB: non c'è un id, la riga non è ancora stata salvata.
  // Usati solo se [onDraftSaved] è valorizzato.
  final DateTime? draftDate;
  final double? draftAmount;
  final TransactionType? draftType;
  final String? draftNote;
  final SubCategorySelection? draftSelection;

  /// Se valorizzato, il pulsante Salva richiama questa callback con
  /// l'operazione compilata invece di scrivere sul database (e salta il
  /// controllo doppioni, già gestito a monte dalla schermata chiamante).
  /// Usato dall'import estratto conto per modificare una riga prima di
  /// confermare l'intero import.
  final ValueChanged<TransactionEntity>? onDraftSaved;

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

  /// Id della spesa a cui il rimborso è collegato (null = rimborso libero).
  int? _refundOfId;

  /// Spesa collegata, tenuta per mostrarne i dettagli nel form (dalla spesa
  /// passata a `refundOf`, o scelta dal selettore).
  TransactionEntity? _linkedExpense;

  bool get _isEditing => widget.existing != null;
  bool get _isDraft => widget.onDraftSaved != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final r = widget.refundOf;
    if (e != null) {
      _type = e.type;
      _amount = e.amount;
      _date = e.date;
      _isExtraordinary = e.isExtraordinary;
      _isRefund = e.isRefund;
      _refundOfId = e.refundOfId;
      _noteController.text = e.note ?? '';
      if (e.subCategoryId != null) {
        _selection = SubCategorySelection(
          categoryId: e.categoryId,
          subCategoryId: e.subCategoryId!,
        );
      }
    } else if (_isDraft) {
      if (widget.draftType != null) _type = widget.draftType!;
      if (widget.draftAmount != null) _amount = widget.draftAmount!;
      if (widget.draftDate != null) _date = widget.draftDate!;
      _noteController.text = widget.draftNote ?? '';
      _selection = widget.draftSelection;
    } else if (r != null) {
      // Rimborso avviato da una spesa esistente: eredita categoria, data e
      // sottocategoria; l'importo lo inserisce l'utente.
      _isRefund = true;
      _type = TransactionType.expense;
      _date = r.date;
      _refundOfId = r.id;
      _linkedExpense = r;
      if (r.subCategoryId != null) {
        _selection = SubCategorySelection(
          categoryId: r.categoryId,
          subCategoryId: r.subCategoryId!,
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

  /// Apre il selettore delle spese esistenti da collegare al rimborso.
  Future<void> _pickExpenseToRefund() async {
    final all = ref.read(allTransactionsProvider).valueOrNull ?? const [];
    final categories = ref.read(allCategoriesProvider).valueOrNull ?? const [];
    final catById = {for (final c in categories) c.id: c};
    final expenses = all
        .where((t) =>
            t.type == TransactionType.expense &&
            !t.isRefund &&
            t.id != null &&
            t.id != widget.existing?.id)
        .toList();

    if (expenses.isEmpty) {
      showErrorSnackBar(context, 'Nessuna spesa da collegare');
      return;
    }

    final picked = await showModalBottomSheet<TransactionEntity>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExpensePickerSheet(expenses: expenses, catById: catById),
    );
    if (picked != null) {
      setState(() {
        _linkedExpense = picked;
        _refundOfId = picked.id;
        _isRefund = true;
        _type = TransactionType.expense;
        _date = picked.date; // eredita la data della spesa (modificabile)
        if (picked.subCategoryId != null) {
          _selection = SubCategorySelection(
            categoryId: picked.categoryId,
            subCategoryId: picked.subCategoryId!,
          );
        }
      });
    }
  }

  /// Interroga il database (non la cache in memoria) per una transazione
  /// attiva con stessa data (giorno), categoria e importo di quella che si
  /// sta per salvare: probabile doppione (es. scontrino inserito due volte
  /// per errore). Va chiamato prima di generare la nuova transazione.
  Future<TransactionEntity?> _findPossibleDuplicate() async {
    final matches = await ref.read(searchTransactionsProvider).call(
          SearchTransactionsParams(
            categoryId: _selection!.categoryId,
            amount: _amount,
            date: _date,
          ),
        );
    return matches.isEmpty ? null : matches.first;
  }

  /// Mostra il dialog di avviso doppione, con link alla spesa di riferimento;
  /// true se l'utente conferma comunque il salvataggio.
  Future<bool> _confirmPossibleDuplicate(TransactionEntity match) async {
    final categories = ref.read(allCategoriesProvider).valueOrNull ?? const [];
    var catName = 'Senza categoria';
    for (final c in categories) {
      if (c.id == match.categoryId) {
        catName = c.name;
        break;
      }
    }
    final hasNote = match.note?.isNotEmpty == true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Possibile doppione'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Questa spesa potrebbe già essere stata inserita. '
              'Vuoi inserirla comunque?',
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.link),
                title: Text(hasNote ? match.note! : catName),
                subtitle: Text(
                  '$catName · ${AppFormatters.shortDate(match.date)} · '
                  '${AppFormatters.currency(match.amount)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Chiude il dialog (l'utente sta abbandonando questa
                  // operazione per andare a controllare quella esistente) e
                  // apre la spesa di riferimento.
                  Navigator.of(dialogContext).pop(false);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddTransactionPage(existing: match),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salva comunque'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _save() async {
    if (!_canSave) return;

    // Solo per operazioni nuove: in modifica l'utente sta correggendo un
    // movimento già esistente, un rimborso è già esplicitamente collegato a
    // una spesa scelta dall'utente (quindi non è un doppione), e una bozza di
    // import ha già il suo controllo doppioni nella schermata chiamante.
    if (!_isEditing && !_isRefund && !_isDraft) {
      final duplicate = await _findPossibleDuplicate();
      if (!mounted) return;
      if (duplicate != null) {
        final proceed = await _confirmPossibleDuplicate(duplicate);
        if (!mounted || !proceed) return;
      }
    }

    setState(() => _saving = true);

    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
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
      // Il collegamento vale solo per i rimborsi.
      refundOfId: _isRefund ? _refundOfId : null,
      merchantId: widget.existing?.merchantId,
      receiptImagePath: widget.existing?.receiptImagePath,
      recurringId: widget.existing?.recurringId,
    );

    if (_isDraft) {
      widget.onDraftSaved!(entity);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

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
    // Risolve la spesa collegata per la visualizzazione (se in modifica di un
    // rimborso già collegato non abbiamo l'oggetto in memoria).
    final all = ref.watch(allTransactionsProvider).valueOrNull ?? const [];
    final categories = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    final catById = {for (final c in categories) c.id: c};
    TransactionEntity? linked = _linkedExpense;
    if (linked == null && _refundOfId != null) {
      for (final t in all) {
        if (t.id == _refundOfId) {
          linked = t;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_isEditing || _isDraft
            ? 'Modifica operazione'
            : 'Aggiungi Transazione'),
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
              initialAmount: widget.existing?.amount ?? widget.draftAmount,
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
                if (v) {
                  _type = TransactionType.expense;
                } else {
                  // Disattivando il rimborso si scollega la spesa.
                  _refundOfId = null;
                  _linkedExpense = null;
                }
                _selection = null;
              }),
              title: const Text('Rimborso ricevuto'),
              subtitle: const Text('Riduce la spesa della categoria scelta'),
            ),
            if (_isRefund) ...[
              const SizedBox(height: 4),
              _LinkedExpenseField(
                linked: linked,
                category: linked == null ? null : catById[linked.categoryId],
                onPick: _pickExpenseToRefund,
                onClear: () => setState(() {
                  _refundOfId = null;
                  _linkedExpense = null;
                }),
              ),
            ],
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

/// Riga "Collega a una spesa" mostrata quando l'operazione è un rimborso.
class _LinkedExpenseField extends StatelessWidget {
  const _LinkedExpenseField({
    required this.linked,
    required this.category,
    required this.onPick,
    required this.onClear,
  });

  final TransactionEntity? linked;
  final Category? category;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (linked == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.link),
        label: const Text('Collega a una spesa (opzionale)'),
      );
    }

    final hasNote = linked!.note?.isNotEmpty == true;
    final catName = category?.name ?? 'Senza categoria';
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.link, color: theme.colorScheme.primary),
        title: Text(hasNote ? linked!.note! : catName),
        subtitle: Text(
          '$catName · ${AppFormatters.shortDate(linked!.date)} · '
          '${AppFormatters.currency(linked!.amount)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Cambia spesa',
              onPressed: onPick,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Scollega',
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet con l'elenco delle spese esistenti, per collegarne una al
/// rimborso. Ricerca per note/categoria/importo.
class _ExpensePickerSheet extends StatefulWidget {
  const _ExpensePickerSheet({required this.expenses, required this.catById});

  final List<TransactionEntity> expenses;
  final Map<int, Category> catById;

  @override
  State<_ExpensePickerSheet> createState() => _ExpensePickerSheetState();
}

class _ExpensePickerSheetState extends State<_ExpensePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.expenses
        : widget.expenses.where((t) {
            final cat = widget.catById[t.categoryId]?.name ?? '';
            final hay = [
              t.note ?? '',
              cat,
              AppFormatters.shortDate(t.date),
              t.amount.toStringAsFixed(2).replaceAll('.', ','),
            ].join(' ').toLowerCase();
            return hay.contains(_query);
          }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Cerca la spesa da rimborsare...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_outlined,
                      message: 'Nessun risultato',
                      padding: EdgeInsets.symmetric(vertical: 24),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final t = filtered[i];
                        final cat = widget.catById[t.categoryId];
                        final hasNote = t.note?.isNotEmpty == true;
                        final catName = cat?.name ?? 'Senza categoria';
                        return ListTile(
                          leading: Text(cat?.icon ?? '💶',
                              style: const TextStyle(fontSize: 20)),
                          title: Text(hasNote ? t.note! : catName),
                          subtitle: Text(
                            '$catName · ${AppFormatters.shortDate(t.date)}',
                          ),
                          trailing: Text(AppFormatters.currency(t.amount)),
                          onTap: () => Navigator.of(context).pop(t),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
