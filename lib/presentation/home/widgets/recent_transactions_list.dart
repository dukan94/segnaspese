import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/category_providers.dart';
import '../../../core/di/transaction_providers.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/transaction_entity.dart';

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

    return Column(
      children: [
        for (final transaction in transactions)
          _TransactionTile(
            transaction: transaction,
            categoryIcon: categoriesAsync.maybeWhen(
              data: (categories) => categories
                  .where((c) => c.id == transaction.categoryId)
                  .map((c) => c.icon)
                  .firstOrNull,
              orElse: () => null,
            ),
            categoryName: categoriesAsync.maybeWhen(
              data: (categories) => categories
                  .where((c) => c.id == transaction.categoryId)
                  .map((c) => c.name)
                  .firstOrNull,
              orElse: () => null,
            ),
          ),
      ],
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.transaction,
    required this.categoryIcon,
    required this.categoryName,
  });

  final TransactionEntity transaction;
  final String? categoryIcon;
  final String? categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIncome = transaction.type == TransactionType.income;
    final hasNote = transaction.note?.isNotEmpty == true;
    final date = AppFormatters.dayMonth(transaction.date);
    // Se il titolo è la nota (es. il negozio), mostra comunque la categoria nel
    // sottotitolo; altrimenti il titolo è già la categoria e basta la data.
    final base = (hasNote && categoryName != null) ? '$categoryName · $date' : date;
    final subtitle = transaction.isRefund ? 'Rimborso · $base' : base;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Text(categoryIcon ?? '💶', style: const TextStyle(fontSize: 18)),
        ),
        title: Text(hasNote ? transaction.note! : (categoryName ?? 'Senza categoria')),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppFormatters.signedCurrency(transaction.signedAmount),
              style: theme.textTheme.titleSmall?.copyWith(
                color:
                    isIncome ? theme.colorScheme.primary : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Elimina',
              color: theme.colorScheme.outline,
              onPressed: transaction.id == null
                  ? null
                  : () => _confirmDelete(context, ref, transaction),
            ),
          ],
        ),
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

  await ref.read(deleteTransactionProvider).call(transaction.id!);
  if (context.mounted) showSuccessSnackBar(context, 'Operazione eliminata');
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
