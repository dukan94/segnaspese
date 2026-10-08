import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/services/money_rounding.dart';
import '../home/home_providers.dart';
import '../shared_widgets/content_width_limiter.dart';
import '../shared_widgets/empty_state.dart';
import '../shared_widgets/transaction_list_item.dart';
import '../shared_widgets/transaction_row.dart';
import 'transaction_actions.dart';
import 'transaction_lookups.dart';
import 'widgets/transaction_actions_menu.dart';

/// Dettaglio di una transazione in sola lettura (M59): si apre toccando una
/// riga in Home o Storico. Matita in AppBar → modifica, "⋮" → le altre
/// azioni.
///
/// Riceve solo l'id e osserva la transazione dallo stream: dopo una
/// modifica mostra subito i dati aggiornati, e se la transazione sparisce
/// (eliminata via sync da un altro dispositivo) mostra un avviso invece di
/// dati vecchi.
class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({super.key, required this.transactionId});

  final int transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(allTransactionsProvider);
    final lookups = ref.watch(transactionLookupsProvider);
    final tx = lookups.transactionsById[transactionId];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dettaglio'),
        actions: [
          if (tx != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifica',
              onPressed: () => editTransaction(context, tx),
            ),
            TransactionActionsMenu(
              transaction: tx,
              inDetailPage: true,
              onDeleted: () {
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
      body: ContentWidthLimiter(
        child: tx != null
            ? _DetailBody(tx: tx, lookups: lookups)
            : txAsync.isLoading
                ? const Center(child: CircularProgressIndicator())
                : const EmptyState(
                    icon: Icons.delete_outline,
                    message: 'Questa operazione non esiste più.',
                  ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.tx, required this.lookups});

  final TransactionEntity tx;
  final TransactionLookups lookups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = lookups.categoryOf(tx);
    final catName = category?.name ?? 'Senza categoria';
    final subName = lookups.subCategoryNameOf(tx);
    final hasNote = tx.note?.isNotEmpty == true;
    final amount = tx.signedAmount;
    final linkedExpense = lookups.linkedExpenseOf(tx);
    final linkedRefunds = lookups.linkedRefundsOf(tx);

    final typeLabel = tx.isRefund
        ? 'Rimborso su spesa'
        : tx.type == TransactionType.income
            ? 'Entrata'
            : 'Uscita';

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Intestazione: icona categoria, importo grande, nota.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Color(category?.color ?? 0xFF9E9E9E),
                child: Text(category?.icon ?? '💶',
                    style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(height: 10),
              Text(
                AppFormatters.signedCurrency(amount),
                style: AppTheme.amountStyle(theme.textTheme.headlineMedium
                    ?.copyWith(
                  color: amount >= 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                )),
              ),
              const SizedBox(height: 4),
              Text(
                hasNote ? tx.note! : catName,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _InfoRow(label: 'Data', value: AppFormatters.shortDate(tx.date)),
        _InfoRow(label: 'Tipo', value: typeLabel),
        _InfoRow(label: 'Categoria', value: catName),
        if (subName != null)
          _InfoRow(label: 'Sottocategoria', value: subName),
        if (tx.isExtraordinary)
          _InfoRow(
            label: 'Tag',
            value: 'Straordinaria',
            valueColor: AppTheme.onWarningContainer(context),
          ),
        if (tx.recurringId != null)
          const _InfoRow(label: 'Origine', value: 'Generata da ricorrenza'),
        if (linkedExpense != null) ...[
          const _SectionHeader('Spesa collegata'),
          TransactionListItem(transaction: linkedExpense),
          transactionRowDivider,
        ],
        if (linkedRefunds.isNotEmpty)
          ..._buildRefundsSection(context, linkedRefunds),
      ],
    );
  }

  List<Widget> _buildRefundsSection(
    BuildContext context,
    List<TransactionEntity> refunds,
  ) {
    final theme = Theme.of(context);
    final refunded =
        roundToCents(refunds.fold<double>(0, (sum, r) => sum + r.amount));
    final net = roundToCents(tx.amount - refunded);
    final amountStyle = AppTheme.amountStyle(theme.textTheme.bodyMedium);

    return [
      _SectionHeader(
          refunds.length == 1 ? 'Rimborso collegato' : 'Rimborsi collegati'),
      for (final r in refunds) ...[
        TransactionListItem(transaction: r),
        transactionRowDivider,
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
        child: Row(
          children: [
            const Expanded(child: Text('Totale rimborsato')),
            Text(
              AppFormatters.signedCurrency(refunded),
              style: amountStyle.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Text('Costo netto',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(
              AppFormatters.signedCurrency(-net),
              style: amountStyle.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ];
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
