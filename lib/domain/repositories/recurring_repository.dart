import '../entities/recurring_entity.dart';

/// Contratto che il layer Data deve implementare per i movimenti ricorrenti.
/// Il layer Domain/Presentation dipende solo da questa interfaccia, mai
/// dall'implementazione concreta (Drift).
abstract class RecurringRepository {
  /// Tutte le ricorrenze non cancellate (attive prima, poi in pausa).
  Stream<List<RecurringEntity>> watchAll();

  /// Crea una nuova ricorrenza, restituendo il suo id.
  Future<int> add(RecurringEntity recurring);

  /// Aggiorna una ricorrenza esistente.
  Future<void> update(RecurringEntity recurring);

  /// Soft delete di una ricorrenza (coerente con la sync futura, M7).
  Future<void> delete(int id);

  /// Mette in pausa / riattiva una ricorrenza.
  Future<void> setActive(int id, bool active);

  /// Genera le transazioni dovute fino a [asOf] per tutte le ricorrenze
  /// attive, avanzando `nextOccurrence`. Restituisce quante transazioni ha
  /// creato. Chiamata all'avvio dell'app.
  Future<int> generateDue(DateTime asOf);
}
