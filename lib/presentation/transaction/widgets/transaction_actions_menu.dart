import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/transaction_entity.dart';
import '../../shared_widgets/linked_expense_sheet.dart';
import '../transaction_actions.dart';
import '../transaction_lookups.dart';

/// Menu "⋮" delle azioni su una transazione (M59), unico per riga elenco
/// (Home + Storico) e pagina di dettaglio. Raccolte in un menu invece che
/// come icone separate (M36): su schermo stretto più icone affiancate
/// toglievano troppo spazio a nota e importo.
class TransactionActionsMenu extends ConsumerWidget {
  const TransactionActionsMenu({
    super.key,
    required this.transaction,
    this.inDetailPage = false,
    this.onDeleted,
  });

  final TransactionEntity transaction;

  /// Nella pagina di dettaglio "Modifica" è già la matita in AppBar e la
  /// spesa collegata è già una riga tappabile: il menu le omette.
  final bool inDetailPage;

  /// Chiamato dopo un'eliminazione riuscita (il dettaglio si chiude).
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = transaction;
    final lookups = ref.watch(transactionLookupsProvider);
    final linkedExpense = inDetailPage ? null : lookups.linkedExpenseOf(tx);
    final canRefund = canRefundTransaction(tx);

    return PopupMenuButton<VoidCallback>(
      icon: Icon(Icons.more_vert, size: inDetailPage ? null : 20),
      tooltip: 'Altre azioni',
      onSelected: (action) => action(),
      // `_` e non `context`: le azioni devono usare il context della pagina,
      // non quello del menu, che non esiste più dopo la scelta.
      itemBuilder: (_) => [
        if (!inDetailPage)
          PopupMenuItem<VoidCallback>(
            value: () => editTransaction(context, tx),
            child: const _MenuItemContent(
              icon: Icons.edit_outlined,
              label: 'Modifica',
            ),
          ),
        if (linkedExpense != null)
          PopupMenuItem<VoidCallback>(
            value: () => showLinkedExpenseSheet(
              context,
              linkedExpense,
              lookups.categoryOf(linkedExpense),
            ),
            child: const _MenuItemContent(
              icon: Icons.link,
              label: 'Spesa collegata',
            ),
          ),
        if (canRefund)
          PopupMenuItem<VoidCallback>(
            value: () => refundTransaction(context, tx),
            child: const _MenuItemContent(
              icon: Icons.currency_exchange,
              label: 'Rimborsa',
            ),
          ),
        if (canRefund)
          PopupMenuItem<VoidCallback>(
            value: () => splitRefundTransaction(context, ref, tx),
            child: const _MenuItemContent(
              icon: Icons.call_split,
              label: 'Rimborso con divisore',
            ),
          ),
        PopupMenuItem<VoidCallback>(
          value: () async {
            final deleted =
                await confirmAndDeleteTransaction(context, ref, tx);
            if (deleted) onDeleted?.call();
          },
          child: const _MenuItemContent(
            icon: Icons.delete_outline,
            label: 'Elimina',
          ),
        ),
      ],
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
