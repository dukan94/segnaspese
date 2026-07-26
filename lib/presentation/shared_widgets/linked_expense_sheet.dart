import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../domain/entities/transaction_entity.dart';

/// Mostra in un bottom sheet i dettagli della spesa originale a cui un
/// rimborso è collegato (v. Transactions.refundOfId). Usato dall'icona 🔗 sia
/// nello Storico sia nelle "Ultime operazioni" della Home.
Future<void> showLinkedExpenseSheet(
  BuildContext context,
  TransactionEntity expense,
  Category? category,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final hasNote = expense.note?.isNotEmpty == true;
      final catName = category?.name ?? 'Senza categoria';

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Spesa collegata', style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text(category?.icon ?? '💶',
                      style: const TextStyle(fontSize: 18)),
                ),
                title: Text(hasNote ? expense.note! : catName),
                subtitle: Text('$catName · ${AppFormatters.shortDate(expense.date)}'),
                trailing: Text(
                  AppFormatters.currency(expense.amount),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
