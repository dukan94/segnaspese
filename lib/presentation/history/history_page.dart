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
                    return EmptyState(
                      icon: all.isEmpty
                          ? Icons.receipt_long_outlined
                          : Icons.search_off_outlined,
                      message: all.isEmpty
                          ? 'Nessuna operazione'
                          : 'Nessun risultato per "${_searchController.text}"',
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
    if (_query.isEmpty) return all;
    return all.where((t) {
      final cat = catById[t.categoryId]?.name ?? '';
      final subCat =
          t.subCategoryId != null ? (subNameById[t.subCategoryId] ?? '') : '';
      final haystack = [
        t.note ?? '',
        cat,
        subCat,
        AppFormatters.shortDate(t.date),
        t.amount.toStringAsFixed(2),
        t.amount.toStringAsFixed(2).replaceAll('.', ','),
      ].join(' ').toLowerCase();
      return haystack.contains(_query);
    }).toList();
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: cardColor,
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Text(category?.icon ?? '💶',
                  style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 8),
            // Data isolata dal resto del testo (M30): prima era dentro la
            // stringa di subtitle unita con "·", qui ha un suo spazio
            // dedicato invece di essere annegata nel resto.
            Text(
              AppFormatters.dayMonth(tx.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: onCardColor ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
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
          ],
        ),
        subtitle: Text(
          secondLine,
          style: TextStyle(color: onCardColor),
        ),
        onTap: onEdit,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onShowLinked != null)
              IconButton(
                icon: const Icon(Icons.link, size: 20),
                tooltip: 'Spesa collegata',
                color: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
                onPressed: onShowLinked,
              ),
            Text(
              AppFormatters.signedCurrency(tx.signedAmount),
              style: AppTheme.amountStyle(theme.textTheme.titleSmall?.copyWith(
                color: positive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              )),
            ),
            if (onRefund != null)
              IconButton(
                icon: const Icon(Icons.currency_exchange, size: 20),
                tooltip: 'Rimborsa',
                color: theme.colorScheme.outline,
                visualDensity: VisualDensity.compact,
                onPressed: onRefund,
              ),
            if (onSplitRefund != null)
              IconButton(
                icon: const Icon(Icons.call_split, size: 20),
                tooltip: 'Rimborso con divisore',
                color: theme.colorScheme.outline,
                visualDensity: VisualDensity.compact,
                onPressed: onSplitRefund,
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Elimina',
              color: theme.colorScheme.outline,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
