import '../entities/transaction_entity.dart';

/// Contratto che il layer Data deve implementare per le transazioni.
///
/// Il layer Domain/Presentation dipende solo da questa interfaccia, mai
/// dall'implementazione concreta (Drift) o dal SyncService: questo è ciò
/// che permette di aggiungere/sostituire il layer di sync (Turso) senza
/// toccare UseCase o widget.
abstract class TransactionRepository {
  Stream<List<TransactionEntity>> watchAll();

  Stream<List<TransactionEntity>> watchByPeriod({
    required DateTime from,
    required DateTime to,
  });

  Future<List<TransactionEntity>> search({
    String? merchantQuery,
    String? note,
    int? categoryId,
    double? amount,
    DateTime? date,
  });

  Future<int> add(TransactionEntity transaction);

  /// Inserisce più transazioni in modo atomico (usato dall'import CSV):
  /// o vengono salvate tutte, o nessuna.
  Future<void> addAll(List<TransactionEntity> transactions);

  Future<void> update(TransactionEntity transaction);

  /// Soft delete (necessario per propagare la cancellazione in sync).
  Future<void> delete(int id);

  /// Elimina la riga per sempre, bypassando il soft delete (solo pannello
  /// Admin: v. `HardDeleteTransaction`, che avverte del rischio di
  /// ricomparsa via sync se non preceduto da una `syncNow()`).
  Future<void> hardDelete(int id);

  /// Elimina per sempre tutte le transazioni già soft-deleted (pulizia bulk,
  /// solo pannello Admin). Restituisce quante ne ha eliminate.
  Future<int> purgeSoftDeleted();
}
