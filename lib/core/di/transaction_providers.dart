import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/daos/transaction_dao.dart';
import '../../data/repositories_impl/transaction_repository_impl.dart';
import '../../data/services/safe_transaction_deletion_service.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/transaction/add_transaction.dart';
import '../../domain/usecases/transaction/delete_transaction.dart';
import '../../domain/usecases/transaction/search_transactions.dart';
import '../../domain/usecases/transaction/update_transaction.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

/// DAO delle transazioni, ricavato dall'istanza condivisa di [AppDatabase].
final transactionDaoProvider = Provider<TransactionDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.transactionDao;
});

/// Repository astratto: il resto dell'app dipende solo da
/// [TransactionRepository], mai da [TransactionRepositoryImpl] direttamente.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final dao = ref.watch(transactionDaoProvider);
  return TransactionRepositoryImpl(dao);
});

/// Logga un fallimento della sync scatenata dopo un salvataggio (M32): stesso
/// pattern fire-and-forget già usato in `main.dart`/`app.dart` — mai
/// mostrato all'utente, resta visibile solo dall'icona/banner di sync
/// esistenti.
void _logPostSaveSyncError(Object error, StackTrace stackTrace) {
  debugPrint('Sync Turso fallita (dopo salvataggio transazione): $error\n$stackTrace');
}

/// M32: dopo il salvataggio locale, lancia anche una sync Turso in
/// background (oltre a quella già periodica ogni 5 minuti e a quella sui
/// cambi di stato dell'app) — un inserimento/modifica non aspetta più fino
/// al prossimo tick per arrivare sugli altri dispositivi.
final addTransactionProvider =
    Provider<Future<int> Function(TransactionEntity)>((ref) {
  final useCase = AddTransaction(ref.watch(transactionRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (transaction) async {
    final id = await useCase.call(transaction);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
    return id;
  };
});

/// M32: stesso trattamento di [addTransactionProvider] — una cancellazione
/// non sincronizzata prima di chiudere l'app potrebbe "ricomparire" da un
/// altro dispositivo che non l'ha ancora vista.
final deleteTransactionProvider =
    Provider<Future<void> Function(int)>((ref) {
  final useCase = DeleteTransaction(ref.watch(transactionRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (transactionId) async {
    await useCase.call(transactionId);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// Solo pannello Admin: unico punto d'accesso per eliminare per sempre una
/// transazione o pulire quelle già soft-deleted, con verifica sul server
/// prima di ogni eliminazione fisica (v. safe_transaction_deletion_service.dart).
final safeTransactionDeletionServiceProvider =
    Provider<SafeTransactionDeletionService>((ref) {
  return SafeTransactionDeletionService(
    ref.watch(transactionDaoProvider),
    ref.watch(syncServiceProvider),
  );
});

/// M32: stesso trattamento di [addTransactionProvider]/[deleteTransactionProvider].
final updateTransactionProvider =
    Provider<Future<void> Function(TransactionEntity)>((ref) {
  final useCase = UpdateTransaction(ref.watch(transactionRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (transaction) async {
    await useCase.call(transaction);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

final searchTransactionsProvider = Provider<SearchTransactions>((ref) {
  return SearchTransactions(ref.watch(transactionRepositoryProvider));
});

/// Tutte le transazioni di un anno solare. Sorgente condivisa da Dashboard e
/// dal riepilogo/previsione annuale del Budget.
final yearTransactionsProvider =
    StreamProvider.autoDispose.family<List<TransactionEntity>, int>((ref, year) {
  final from = DateTime(year, 1, 1);
  final to = DateTime(year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
  return ref
      .watch(transactionRepositoryProvider)
      .watchByPeriod(from: from, to: to);
});
