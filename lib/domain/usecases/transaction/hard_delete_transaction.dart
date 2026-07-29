import '../../repositories/transaction_repository.dart';

/// Elimina per sempre una transazione, bypassando il soft delete (solo
/// pannello Admin). Chi la usa deve aver già propagato la cancellazione alla
/// sync remota, se configurata, altrimenti la riga può ricomparire da un
/// altro dispositivo alla sync successiva.
class HardDeleteTransaction {
  HardDeleteTransaction(this._repository);

  final TransactionRepository _repository;

  Future<void> call(int transactionId) {
    return _repository.hardDelete(transactionId);
  }
}
