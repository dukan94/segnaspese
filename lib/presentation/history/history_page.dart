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
import '../shared_widgets/empty_state.dart';
import '../shared_widgets/fade_in_item.dart';
import '../shared_widgets/linked_expense_sheet.dart';
import '../transaction/add_transaction_page.dart';

/// Storico: elenco completo delle operazioni con ricerca, modifica ed
/// eliminazione. Raggiungibile dalla barra di navigazione.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _searchController = TextEditingController();
  String _query = '';

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
      body: Column(
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
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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
                    final canRefund =
                        tx.type == TransactionType.expense && !tx.isRefund;
                    return FadeInItem(
                      key: ValueKey(tx.id),
                      child: _HistoryTile(
                        tx: tx,
                        category: catById[tx.categoryId],
                        onEdit: () => _edit(tx),
                        onDelete: () => _confirmDelete(tx),
                        onRefund: canRefund ? () => _refund(tx) : null,
                        linkedExpense: linked,
                        onShowLinked: linked == null
                            ? null
                            : () => showLinkedExpenseSheet(
                                  context,
                                  linked,
                                  catById[linked.categoryId],
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
    this.onRefund,
    this.linkedExpense,
    this.onShowLinked,
  });

  final TransactionEntity tx;
  final Category? category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Avvia un rimborso collegato a questa spesa (solo per le uscite normali).
  final VoidCallback? onRefund;

  /// Spesa originale a cui questo rimborso è collegato (se presente).
  final TransactionEntity? linkedExpense;

  /// Mostra i dettagli della spesa collegata (icona 🔗).
  final VoidCallback? onShowLinked;

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
    final subtitle = [
      if (tags.isNotEmpty) tags.join(' · '),
      catName,
      AppFormatters.shortDate(tx.date),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Text(category?.icon ?? '💶',
              style: const TextStyle(fontSize: 18)),
        ),
        title: Text(hasNote ? tx.note! : catName),
        subtitle: Text(subtitle),
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
