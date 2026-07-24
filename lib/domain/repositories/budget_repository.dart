import '../entities/budget_entity.dart';

/// Contratto che il layer Data deve implementare per i budget. Il layer
/// Domain/Presentation dipende solo da questa interfaccia, mai
/// dall'implementazione concreta (Drift).
abstract class BudgetRepository {
  /// Tutti i budget di un anno (totali mensili + per categoria).
  Stream<List<BudgetEntity>> watchYear(int year);

  /// Tutti i budget di un singolo mese (totale + categorie).
  Stream<List<BudgetEntity>> watchMonth(DateTime month);

  /// Imposta (crea o aggiorna) il budget totale di un mese
  /// (`categoryId == null`) oppure l'allocazione di una categoria in quel mese
  /// (`categoryId` valorizzato).
  Future<void> setBudget({
    int? categoryId,
    required DateTime month,
    required double amount,
  });

  /// Soft delete di un budget (rimozione allocazione categoria o azzeramento
  /// totale del mese).
  Future<void> deleteBudget(int id);
}
