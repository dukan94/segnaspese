import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/transaction_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../domain/entities/transaction_entity.dart';
import 'add_transaction_page.dart';
import 'transaction_detail_page.dart';
import 'transaction_lookups.dart';
import 'widgets/split_refund_sheet.dart';

/// Azioni su una transazione (M59), in un punto solo: usate dal menu "⋮"
/// della riga (Home + Storico) e dalla pagina di dettaglio. Prima Home e
/// Storico avevano ciascuna la propria copia (incluso il dialog di
/// conferma eliminazione).

/// Rimborsa / Rimborso con divisore valgono solo per le spese normali (mai
/// un rimborso di un rimborso, né su un'entrata).
bool canRefundTransaction(TransactionEntity tx) =>
    tx.type == TransactionType.expense && !tx.isRefund;

Future<void> openTransactionDetail(BuildContext context, TransactionEntity tx) {
  if (tx.id == null) return Future.value();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TransactionDetailPage(transactionId: tx.id!),
    ),
  );
}

Future<void> editTransaction(BuildContext context, TransactionEntity tx) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AddTransactionPage(existing: tx)),
  );
}

/// Avvia un rimborso collegato a questa spesa: apre la schermata di
/// inserimento già impostata come rimborso, con categoria e data ereditate.
Future<void> refundTransaction(BuildContext context, TransactionEntity tx) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => AddTransactionPage(refundOf: tx)),
  );
}

Future<void> splitRefundTransaction(
  BuildContext context,
  WidgetRef ref,
  TransactionEntity tx,
) {
  final category = ref.read(transactionLookupsProvider).categoryOf(tx);
  return showSplitRefundSheet(context, tx, category);
}

/// Chiede conferma ed elimina. Ritorna `true` solo se l'eliminazione è
/// andata a buon fine (la pagina di dettaglio lo usa per chiudersi).
Future<bool> confirmAndDeleteTransaction(
  BuildContext context,
  WidgetRef ref,
  TransactionEntity tx,
) async {
  if (tx.id == null) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Elimina operazione'),
      content: const Text('Sei sicuro di voler eliminare questa operazione?'),
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
  if (confirmed != true || !context.mounted) return false;
  try {
    await ref.read(deleteTransactionProvider).call(tx.id!);
    if (context.mounted) showSuccessSnackBar(context, 'Operazione eliminata');
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, 'Errore: $e');
    return false;
  }
}
