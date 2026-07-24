import '../../repositories/transaction_repository.dart';

/// Elimina (soft delete) una transazione esistente, dato il suo id.
class DeleteTransaction {
  DeleteTransaction(this._repository);

  final TransactionRepository _repository;

  Future<void> call(int transactionId) {
    return _repository.delete(transactionId);
  }
}
