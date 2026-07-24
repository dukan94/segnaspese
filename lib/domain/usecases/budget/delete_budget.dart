import '../../repositories/budget_repository.dart';

/// Rimuove (soft delete) un budget: l'allocazione di una categoria in un mese
/// o il totale di un mese.
class DeleteBudget {
  DeleteBudget(this._repository);

  final BudgetRepository _repository;

  Future<void> call(int id) {
    return _repository.deleteBudget(id);
  }
}
