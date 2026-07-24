import '../../entities/transaction_entity.dart';
import '../../repositories/transaction_repository.dart';

/// Registra una nuova transazione (manuale o da scontrino scansionato).
///
/// Incapsula la sola chiamata al repository per ora; punto di estensione
/// naturale per validazioni di business future (es. limiti, alert budget).
class AddTransaction {
  AddTransaction(this._repository);

  final TransactionRepository _repository;

  Future<int> call(TransactionEntity transaction) {
    return _repository.add(transaction);
  }
}
