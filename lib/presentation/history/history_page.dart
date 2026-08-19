import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/categories_table.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/services/money_rounding.dart';
import '../home/home_providers.dart';
import '../shared_widgets/content_width_limiter.dart';
import '../shared_widgets/empty_state.dart';
import '../shared_widgets/fade_in_item.dart';
import '../shared_widgets/linked_expense_sheet.dart';
import '../shared_widgets/linked_refunds_sheet.dart';
import '../transaction/add_transaction_page.dart';
import '../transaction/widgets/split_refund_sheet.dart';

/// Storico: elenco completo delle operazioni con ricerca, modifica ed
/// eliminazione. Raggiungibile dalla barra di navigazione.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.initialQuery});

  /// Precompila la ricerca (es. doppio click su una categoria/sottocategoria
  /// in Dashboard, M34) — l'utente può comunque modificarla o cancellarla
  /// come una ricerca digitata a mano.
  final String? initialQuery;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late final _searchController =
      TextEditingController(text: widget.initialQuery ?? '');
  late String _query = (widget.initialQuery ?? '').trim().toLowerCase();

  // Filtri separati dal testo (M45), combinati in AND con esso e tra loro.
  DateTimeRange? _dateRange;
  double? _minAmount;
  double? _maxAmount;

  bool get _hasDateFilter => _dateRange != null;
  bool get _hasAmountFilter => _minAmount != null || _maxAmount != null;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(allTransactionsProvider);
    final categories = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    final catById = {for (final c in categories) c.id: c};
    // Sottocategorie di entrambi i tipi, solo per il nome nella ricerca (non
    // serve la categoria padre qui, quella è già in catById).
    final expenseSubs = ref
            .watch(subCategoriesForTypeProvider(TransactionKind.expense))
            .valueOrNull ??
        const [];
    final incomeSubs = ref
            .watch(subCategoriesForTypeProvider(TransactionKind.income))
            .valueOrNull ??
        const [];
    final subNameById = {
      for (final s in [...expenseSubs, ...incomeSubs])
        s.subCategory.id: s.subCategory.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Storico')),
      body: ContentWidthLimiter(
        // Stessa larghezza di Home (760): lista a colonna singola, niente
        // master-detail (deciso con Mario per M30). Avvolge tutto il body
        // (ricerca + lista), non solo la lista: altrimenti la barra di
        // ricerca resterebbe stirata a piena larghezza sopra una lista
        // centrata sotto — incoerenza corretta insieme a M31.
        maxWidth: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Cerca per negozio, categoria, sottocategoria, importo, data...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  // Filtri separati per data e importo (M45), a range,
                  // combinati in AND col testo. Icona colorata quando il
                  // filtro è attivo; tocca per impostare, tieni premuto per
                  // rimuovere (stesso principio del pulsante "x" del testo
                  // sopra, solo attivabile invece che sempre visibile).
                  _FilterIconButton(
                    icon: Icons.calendar_month_outlined,
                    active: _hasDateFilter,
                    tooltip: _hasDateFilter
                        ? 'Dal ${AppFormatters.shortDate(_dateRange!.start)} al ${AppFormatters.shortDate(_dateRange!.end)} — tieni premuto per rimuovere'
                        : 'Filtra per data',
                    onTap: _pickDateRange,
                    onLongPress: _hasDateFilter
                        ? () => setState(() => _dateRange = null)
                        : null,
                  ),
                  _FilterIconButton(
                    icon: Icons.euro,
                    active: _hasAmountFilter,
                    tooltip: _hasAmountFilter
                        ? 'Importo ${_minAmount != null ? 'da ${AppFormatters.currency(_minAmount!)} ' : ''}${_maxAmount != null ? 'a ${AppFormatters.currency(_maxAmount!)}' : ''} — tieni premuto per rimuovere'
                        : 'Filtra per importo',
                    onTap: _pickAmountRange,
                    onLongPress: _hasAmountFilter
                        ? () => setState(() {
                              _minAmount = null;
                              _maxAmount = null;
                            })
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: txAsync.when(
                data: (all) {
                  final filtered = _filter(all, catById, subNameById);
                  // Lookup id → transazione, per risolvere la spesa collegata a
                  // un rimborso (refundOfId).
                  final byId = {
                    for (final t in all)
                      if (t.id != null) t.id!: t,
                  };
                  // Direzione opposta: spesa → rimborsi collegati (una spesa
                  // può averne più di uno, v. M25 "nessun tetto sui rimborsi").
                  final refundsByExpenseId = <int, List<TransactionEntity>>{};
                  for (final t in all) {
                    final expenseId = t.refundOfId;
                    if (expenseId != null) {
                      refundsByExpenseId
                          .putIfAbsent(expenseId, () => [])
                          .add(t);
                    }
                  }
                  if (filtered.isEmpty) {
                    final hasAnyFilter = _query.isNotEmpty ||
                        _hasDateFilter ||
                        _hasAmountFilter;
                    return EmptyState(
                      icon: all.isEmpty
                          ? Icons.receipt_long_outlined
                          : Icons.search_off_outlined,
                      message: all.isEmpty
                          ? 'Nessuna operazione'
                          : _query.isNotEmpty
                              ? 'Nessun risultato per "${_searchController.text}"'
                              : hasAnyFilter
                                  ? 'Nessun risultato con i filtri impostati'
                                  : 'Nessun risultato',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final tx = filtered[i];
                      final linked =
                          tx.refundOfId != null ? byId[tx.refundOfId] : null;
                      final linkedRefunds =
                          tx.id != null ? refundsByExpenseId[tx.id!] : null;
                      final canRefund =
                          tx.type == TransactionType.expense && !tx.isRefund;
                      return FadeInItem(
                        key: ValueKey(tx.id),
                        child: _HistoryTile(
                          tx: tx,
                          category: catById[tx.categoryId],
                          subCategoryName: tx.subCategoryId != null
                              ? subNameById[tx.subCategoryId]
                              : null,
                          onEdit: () => _edit(tx),
                          onDelete: () => _confirmDelete(tx),
                          onRefund: canRefund ? () => _refund(tx) : null,
                          onSplitRefund: canRefund
                              ? () => showSplitRefundSheet(
                                    context,
                                    tx,
                                    catById[tx.categoryId],
                                  )
                              : null,
                          linkedExpense: linked,
                          onShowLinked: linked == null
                              ? null
                              : () => showLinkedExpenseSheet(
                                    context,
                                    linked,
                                    catById[linked.categoryId],
                                  ),
                          linkedRefunds: linkedRefunds,
                          onShowLinkedRefunds:
                              (linkedRefunds == null || linkedRefunds.isEmpty)
                                  ? null
                                  : () => showLinkedRefundsSheet(
                                        context,
                                        linkedRefunds,
                                        catById[tx.categoryId],
                                      ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Errore: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TransactionEntity> _filter(
    List<TransactionEntity> all,
    Map<int, Category> catById,
    Map<int, String> subNameById,
  ) {
    Iterable<TransactionEntity> result = all;

    // Filtro data (M45): confronto solo su anno/mese/giorno, ignorando
    // l'orario — DateTimeRange.end da showDateRangePicker è mezzanotte del
    // giorno scelto, non fine giornata, quindi va normalizzato allo stesso
    // modo di start per includere quel giorno.
    final range = _dateRange;
    if (range != null) {
      final from = DateTime(range.start.year, range.start.month, range.start.day);
      final to = DateTime(range.end.year, range.end.month, range.end.day);
      result = result.where((t) {
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return !d.isBefore(from) && !d.isAfter(to);
      });
    }

    // Filtro importo (M45): sempre arrotondato ai centesimi, stessa
    // precauzione degli altri confronti su double nel progetto (M42).
    if (_minAmount != null || _maxAmount != null) {
      final min = _minAmount != null ? roundToCents(_minAmount!) : null;
      final max = _maxAmount != null ? roundToCents(_maxAmount!) : null;
      result = result.where((t) {
        final amount = roundToCents(t.amount);
        if (min != null && amount < min) return false;
        if (max != null && amount > max) return false;
        return true;
      });
    }

    if (_query.isNotEmpty) {
      result = result.where((t) {
        final cat = catById[t.categoryId]?.name ?? '';
        final subCat = t.subCategoryId != null
            ? (subNameById[t.subCategoryId] ?? '')
            : '';
        final haystack = [
          t.note ?? '',
          cat,
          subCat,
          AppFormatters.shortDate(t.date),
          t.amount.toStringAsFixed(2),
          t.amount.toStringAsFixed(2).replaceAll('.', ','),
        ].join(' ').toLowerCase();
        return haystack.contains(_query);
      });
    }

    return result.toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _pickAmountRange() async {
    final minController = TextEditingController(
      text: _minAmount != null ? _minAmount!.toStringAsFixed(2) : '',
    );
    final maxController = TextEditingController(
      text: _maxAmount != null ? _maxAmount!.toStringAsFixed(2) : '',
    );
    final result = await showDialog<(double?, double?)?>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void apply() {
              final minText = minController.text.trim().replaceAll(',', '.');
              final maxText = maxController.text.trim().replaceAll(',', '.');
              final min = minText.isEmpty ? null : double.tryParse(minText);
              final max = maxText.isEmpty ? null : double.tryParse(maxText);
              if ((minText.isNotEmpty && min == null) ||
                  (maxText.isNotEmpty && max == null)) {
                setDialogState(() => error = 'Importo non valido');
                return;
              }
              if (min != null && max != null && min > max) {
                setDialogState(
                    () => error = 'Il minimo non può superare il massimo');
                return;
              }
              Navigator.of(context).pop((min, max));
            }

            return AlertDialog(
              title: const Text('Filtra per importo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: minController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Importo minimo (€)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Importo massimo (€)'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                ],
              ),
              actions: [
                if (_hasAmountFilter)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop((null, null)),
                    child: const Text('Rimuovi filtro'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: apply,
                  child: const Text('Applica'),
                ),
              ],
            );
          },
        );
      },
    );
    minController.dispose();
    maxController.dispose();
    if (result != null && mounted) {
      setState(() {
        _minAmount = result.$1;
        _maxAmount = result.$2;
      });
    }
  }

  Future<void> _edit(TransactionEntity tx) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddTransactionPage(existing: tx)),
    );
  }

  /// Avvia un rimborso collegato a questa spesa: apre la schermata di
  /// inserimento già impostata come rimborso, con categoria e data ereditate.
  Future<void> _refund(TransactionEntity tx) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddTransactionPage(refundOf: tx)),
    );
  }

  Future<void> _confirmDelete(TransactionEntity tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina operazione'),
        content: const Text('Sei sicuro di voler eliminare questa spesa?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || tx.id == null || !mounted) return;
    try {
      await ref.read(deleteTransactionProvider).call(tx.id!);
      if (mounted) showSuccessSnackBar(context, 'Operazione eliminata');
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'Errore: $e');
    }
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.tx,
    required this.category,
    required this.onEdit,
    required this.onDelete,
    this.subCategoryName,
    this.onRefund,
    this.onSplitRefund,
    this.linkedExpense,
    this.onShowLinked,
    this.linkedRefunds,
    this.onShowLinkedRefunds,
  });

  final TransactionEntity tx;
  final Category? category;

  /// Nome della sottocategoria, se impostata (mostrato sotto la Nota, M30).
  final String? subCategoryName;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Avvia un rimborso collegato a questa spesa (solo per le uscite normali).
  final VoidCallback? onRefund;

  /// Rimborso con divisore (M25): quota rapida di questa spesa, senza
  /// passare dal form completo. Stessa condizione di visibilità di
  /// [onRefund] (solo uscite normali, mai un rimborso di un rimborso).
  final VoidCallback? onSplitRefund;

  /// Spesa originale a cui questo rimborso è collegato (se presente).
  final TransactionEntity? linkedExpense;

  /// Mostra i dettagli della spesa collegata (icona 🔗).
  final VoidCallback? onShowLinked;

  /// Rimborsi già collegati a questa spesa (direzione opposta di
  /// [linkedExpense]), se presenti — una spesa può averne più di uno (M25).
  final List<TransactionEntity>? linkedRefunds;

  /// Mostra il/i rimborsi collegati a questa spesa (icona 🔗 accanto alla
  /// Nota, M30) — non null solo se [linkedRefunds] non è vuota.
  final VoidCallback? onShowLinkedRefunds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = tx.signedAmount >= 0;
    final hasNote = tx.note?.isNotEmpty == true;
    final catName = category?.name ?? 'Senza categoria';

    final tags = <String>[
      if (tx.isRefund) 'Rimborso',
      if (tx.isExtraordinary) 'Straordinaria',
    ];
    // Sottocategoria sotto la Nota (M30): se non impostata, il nome
    // categoria resta un'informazione di ripiego valida (l'icona a sinistra
    // già comunica la categoria, ma il testo non deve restare vuoto).
    final secondLine = [subCategoryName ?? catName, ...tags].join(' · ');

    // Un rimborso non ha più uno sfondo dedicato (deciso da Mario dopo aver
    // visto la prima versione a schermo): resta identico a una spesa
    // normale, solo il badge sotto su "spesa già rimborsata" usa un colore.
    Color? cardColor;
    Color? onCardColor;
    if (tx.type == TransactionType.income) {
      cardColor = AppTheme.incomeContainer(context);
      onCardColor = AppTheme.onIncomeContainer(context);
    }

    // Card ricostruita su due righe invece di un ListTile (M36, 18 ago 2026):
    // in un ListTile, trailing (importo + menu azioni) sottrae larghezza
    // condivisa sia a title sia a subtitle, anche se solo la prima riga
    // (Nota) ha davvero bisogno di stare accanto all'importo — su schermo
    // stretto (telefono) la sottocategoria in subtitle restava comunque
    // schiacciata dallo stesso trailing, indipendentemente dal numero di
    // icone. Qui la riga 2 (sottocategoria/tag) ha la larghezza piena della
    // card, non condivisa con l'importo.
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Data sotto l'icona invece che accanto (M36): sulla riga
                  // 1 restava poco spazio per la Nota tra icona+data e
                  // importo+menu, specie su schermo stretto — qui il blocco
                  // icona+data è largo solo quanto l'icona.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        child: Text(category?.icon ?? '💶',
                            style: const TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppFormatters.dayMonth(tx.date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              onCardColor ?? theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasNote ? tx.note! : catName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onCardColor),
                    ),
                  ),
                  if (onShowLinkedRefunds != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: 'Rimborsi collegati',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onShowLinkedRefunds,
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: AppTheme.refundedBadgeColor,
                            child: Icon(
                              Icons.link,
                              size: 14,
                              color: AppTheme.onRefundedBadgeColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    AppFormatters.signedCurrency(tx.signedAmount),
                    style:
                        AppTheme.amountStyle(theme.textTheme.titleSmall?.copyWith(
                      color: positive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    )),
                  ),
                  // Azioni raccolte in un menu a comparsa (M36): con
                  // rimborsa + rimborso con divisore + elimina come icone
                  // separate, questa riga arrivava a occupare gran parte
                  // della larghezza disponibile su schermo stretto. Un solo
                  // pulsante "⋮" resta sempre largo importo + un'icona sola.
                  PopupMenuButton<VoidCallback>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: 'Altre azioni',
                    onSelected: (action) => action(),
                    itemBuilder: (context) => [
                      if (onShowLinked != null)
                        PopupMenuItem<VoidCallback>(
                          value: onShowLinked!,
                          child: const _MenuItemContent(
                            icon: Icons.link,
                            label: 'Spesa collegata',
                          ),
                        ),
                      if (onRefund != null)
                        PopupMenuItem<VoidCallback>(
                          value: onRefund!,
                          child: const _MenuItemContent(
                            icon: Icons.currency_exchange,
                            label: 'Rimborsa',
                          ),
                        ),
                      if (onSplitRefund != null)
                        PopupMenuItem<VoidCallback>(
                          value: onSplitRefund!,
                          child: const _MenuItemContent(
                            icon: Icons.call_split,
                            label: 'Rimborso con divisore',
                          ),
                        ),
                      PopupMenuItem<VoidCallback>(
                        value: onDelete,
                        child: const _MenuItemContent(
                          icon: Icons.delete_outline,
                          label: 'Elimina',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Riga 2: allineata sotto la Nota (dopo icona categoria + data
              // + spaziatura), larghezza piena non condivisa con l'importo.
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Text(
                  secondLine,
                  style: TextStyle(color: onCardColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItemContent extends StatelessWidget {
  const _MenuItemContent({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// Icona filtro accanto alla ricerca (M45): colorata quando il filtro è
/// attivo, tocca per impostare/modificare, tieni premuto per rimuovere.
class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 22,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
