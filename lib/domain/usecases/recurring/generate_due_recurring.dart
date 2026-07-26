import '../../repositories/recurring_repository.dart';

/// Genera le transazioni dovute da tutte le ricorrenze attive fino a oggi.
///
/// Va invocata all'avvio dell'app: se l'app non viene aperta per più periodi,
/// recupera tutte le occorrenze mancanti (es. due mesi di Netflix non ancora
/// generati). Restituisce il numero di transazioni create.
class GenerateDueRecurring {
  GenerateDueRecurring(this._repository);

  final RecurringRepository _repository;

  Future<int> call({DateTime? asOf}) {
    return _repository.generateDue(asOf ?? DateTime.now());
  }
}
