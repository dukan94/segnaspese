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

  Future<void> update(TransactionEntity transaction);

  /// Soft delete (necessario per propagare la cancellazione in sync).
  Future<void> delete(int id);
}
