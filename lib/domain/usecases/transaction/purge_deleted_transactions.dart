import '../../repositories/transaction_repository.dart';

/// Elimina per sempre tutte le transazioni già soft-deleted (pulizia bulk,
/// solo pannello Admin). Restituisce quante ne ha eliminate.
class PurgeDeletedTransactions {
  PurgeDeletedTransactions(this._repository);

  final TransactionRepository _repository;

  Future<int> call() {
    return _repository.purgeSoftDeleted();
  }
}
