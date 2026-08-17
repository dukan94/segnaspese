import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../domain/entities/transaction_entity.dart';

/// Mostra in un bottom sheet i rimborsi già collegati a questa spesa
/// (v. Transactions.refundOfId) — direzione opposta di
/// `linked_expense_sheet.dart` (che risale dal rimborso alla spesa
/// originale). Una spesa può avere più di un rimborso collegato (v. M25,
/// nessun tetto sui rimborsi collegati), quindi la lista non è mai
/// assunta di lunghezza 1.
Future<void> showLinkedRefundsSheet(
  BuildContext context,
  List<TransactionEntity> refunds,
  Category? category,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
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
                  Text(
                    refunds.length == 1
                        ? 'Rimborso collegato'
                        : '${refunds.length} rimborsi collegati',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final refund in refunds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(category?.icon ?? '💶',
                        style: const TextStyle(fontSize: 18)),
                  ),
                  title: Text(
                      refund.note?.isNotEmpty == true ? refund.note! : catName),
                  subtitle: Text(AppFormatters.shortDate(refund.date)),
                  trailing: Text(
                    AppFormatters.currency(refund.amount),
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
