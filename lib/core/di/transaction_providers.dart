import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/daos/transaction_dao.dart';
import '../../data/repositories_impl/transaction_repository_impl.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../../domain/usecases/transaction/add_transaction.dart';
import '../../domain/usecases/transaction/delete_transaction.dart';
import '../../domain/usecases/transaction/search_transactions.dart';
import '../../domain/usecases/transaction/update_transaction.dart';
import 'database_provider.dart';

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

final addTransactionProvider = Provider<AddTransaction>((ref) {
  return AddTransaction(ref.watch(transactionRepositoryProvider));
});

final deleteTransactionProvider = Provider<DeleteTransaction>((ref) {
  return DeleteTransaction(ref.watch(transactionRepositoryProvider));
});

final updateTransactionProvider = Provider<UpdateTransaction>((ref) {
  return UpdateTransaction(ref.watch(transactionRepositoryProvider));
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
