import '../../entities/transaction_entity.dart';
import '../../repositories/transaction_repository.dart';

/// Aggiorna un'operazione esistente (richiede id valorizzato).
class UpdateTransaction {
  UpdateTransaction(this._repository);

  final TransactionRepository _repository;

  Future<void> call(TransactionEntity transaction) {
    return _repository.update(transaction);
  }
}
