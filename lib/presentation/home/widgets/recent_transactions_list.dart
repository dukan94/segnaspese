import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/category_providers.dart';
import '../../../core/di/transaction_providers.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/transaction_entity.dart';
import '../../shared_widgets/linked_expense_sheet.dart';
import '../../shared_widgets/transaction_row.dart';
import '../../transaction/add_transaction_page.dart';
import '../home_providers.dart';

/// Lista "Ultime operazioni" della Home. Risolve categoria/icona tramite
/// [allCategoriesProvider] (semplice lookup per id, niente join SQL: per i
/// volumi di un'app di finanza personale è più che sufficiente).
class RecentTransactionsList extends ConsumerWidget {
  const RecentTransactionsList({super.key, required this.transactions});

  final List<TransactionEntity> transactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (transactions.isEmpty) {
      return const _EmptyState();
    }

    final categoriesAsync = ref.watch(allCategoriesProvider);
    // Lookup id → categoria costruito una sola volta, invece di scandire la
    // lista categorie per ogni riga (due volte, per icona e nome).
    final categoriesById = <int, Category>{
      for (final c in categoriesAsync.asData?.value ?? const <Category>[])
        c.id: c,
    };

    // Lookup id → transazione, per risolvere la spesa collegata a un rimborso.
    final allTx = ref.watch(allTransactionsProvider).asData?.value ??
        const <TransactionEntity>[];
    final txById = <int, TransactionEntity>{
      for (final t in allTx)
        if (t.id != null) t.id!: t,
    };

    return Column(
      children: [
        for (var i = 0; i < transactions.length; i++) ...[
          if (i > 0) transactionRowDivider,
          _TransactionTile(
            transaction: transactions[i],
            category: categoriesById[transactions[i].categoryId],
            linkedExpense: transactions[i].refundOfId != null
                ? txById[transactions[i].refundOfId]
                : null,
            categoriesById: categoriesById,
          ),
        ],
      ],
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.transaction,
    required this.category,
    this.linkedExpense,
    this.categoriesById = const {},
  });

  final TransactionEntity transaction;
  final Category? category;

  /// Spesa originale a cui un eventuale rimborso è collegato.
  final TransactionEntity? linkedExpense;
  final Map<int, Category> categoriesById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNote = transaction.note?.isNotEmpty == true;
    // Se il titolo è la nota (es. il negozio), mostra comunque la categoria
    // nella riga sotto; altrimenti il titolo è già la categoria e la riga
    // sotto mostrerebbe un'inutile ripetizione, quindi resta vuota (a meno
    // di tag di stato, es. "Rimborso").
    final leadingMeta = hasNote ? category?.name : null;

    return TransactionRow(
      icon: category?.icon ?? '💶',
      iconColor: category?.color ?? 0xFF9E9E9E,
      title: hasNote ? transaction.note! : (category?.name ?? 'Senza categoria'),
      meta: buildMetaLine(
        context,
        leading: leadingMeta,
        isRefund: transaction.isRefund,
      ),
      date: AppFormatters.dayMonth(transaction.date),
      amount: transaction.signedAmount,
      // Stesso comportamento dello Storico: tocca la riga per modificare
      // l'operazione (le icone in trailing restano tappabili a parte).
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddTransactionPage(existing: transaction)),
      ),
      trailingActions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (linkedExpense != null)
            IconButton(
              icon: const Icon(Icons.link, size: 20),
              tooltip: 'Spesa collegata',
              color: Theme.of(context).colorScheme.primary,
              visualDensity: VisualDensity.compact,
              onPressed: () => showLinkedExpenseSheet(
                context,
                linkedExpense!,
                categoriesById[linkedExpense!.categoryId],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Elimina',
            color: Theme.of(context).colorScheme.outline,
            visualDensity: VisualDensity.compact,
            onPressed: transaction.id == null
                ? null
                : () => _confirmDelete(context, ref, transaction),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  TransactionEntity transaction,
) async {
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
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(deleteTransactionProvider).call(transaction.id!);
    if (context.mounted) showSuccessSnackBar(context, 'Operazione eliminata');
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, 'Errore: $e');
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            'Nessuna operazione registrata',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
