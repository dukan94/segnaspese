import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/transaction_entity.dart';
import '../transaction/transaction_actions.dart';
import '../transaction/transaction_lookups.dart';
import '../transaction/widgets/transaction_actions_menu.dart';
import 'linked_refunds_sheet.dart';
import 'transaction_row.dart';

/// Una transazione in un elenco (M59): unico modo di mostrarla sia in Home
/// ("Ultime operazioni") sia in Storico — prima ognuna aveva il proprio
/// wrapper attorno a [TransactionRow], con informazioni e azioni diverse.
///
/// Tocca la riga → pagina di dettaglio; menu "⋮" → Modifica e le altre
/// azioni ([TransactionActionsMenu]).
class TransactionListItem extends ConsumerWidget {
  const TransactionListItem({super.key, required this.transaction});

  final TransactionEntity transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = transaction;
    final lookups = ref.watch(transactionLookupsProvider);
    final category = lookups.categoryOf(tx);
    final catName = category?.name ?? 'Senza categoria';
    final hasNote = tx.note?.isNotEmpty == true;
    final linkedRefunds = lookups.linkedRefundsOf(tx);

    // Sottocategoria sotto la Nota (M30): se non impostata, il nome
    // categoria resta un ripiego valido (il testo non deve restare vuoto).
    return TransactionRow(
      icon: category?.icon ?? '💶',
      iconColor: category?.color ?? 0xFF9E9E9E,
      title: hasNote ? tx.note! : catName,
      meta: buildMetaLine(
        context,
        leading: lookups.subCategoryNameOf(tx) ?? catName,
        isRefund: tx.isRefund,
        isExtraordinary: tx.isExtraordinary,
      ),
      date: AppFormatters.dayMonth(tx.date),
      amount: tx.signedAmount,
      onTap: () => openTransactionDetail(context, tx),
      badge: linkedRefunds.isEmpty
          ? null
          : Tooltip(
              message: 'Rimborsi collegati',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () =>
                    showLinkedRefundsSheet(context, linkedRefunds, category),
                child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: AppTheme.refundedBadgeColor,
                  child: Icon(
                    Icons.link,
                    size: 13,
                    color: AppTheme.onRefundedBadgeColor,
                  ),
                ),
              ),
            ),
      trailingActions: TransactionActionsMenu(transaction: tx),
    );
  }
}
