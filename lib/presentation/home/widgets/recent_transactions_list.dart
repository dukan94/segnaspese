import 'package:flutter/material.dart';

import '../../../domain/entities/transaction_entity.dart';
import '../../shared_widgets/transaction_list_item.dart';
import '../../shared_widgets/transaction_row.dart';

/// Lista "Ultime operazioni" della Home. Stessa riga dello Storico
/// ([TransactionListItem], M59): stesse informazioni, stesso menu "⋮",
/// tocca per aprire il dettaglio.
class RecentTransactionsList extends StatelessWidget {
  const RecentTransactionsList({super.key, required this.transactions});

  final List<TransactionEntity> transactions;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const _EmptyState();
    }

    return Column(
      children: [
        for (var i = 0; i < transactions.length; i++) ...[
          if (i > 0) transactionRowDivider,
          TransactionListItem(transaction: transactions[i]),
        ],
      ],
    );
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
