import '../../repositories/budget_repository.dart';

/// Imposta il budget totale di un mese (non legato a una categoria).
/// Modificarlo aggiorna la riga del mese; ogni mese resta indipendente.
class SetMonthlyBudget {
  SetMonthlyBudget(this._repository);

  final BudgetRepository _repository;

  Future<void> call({required DateTime month, required double amount}) {
    return _repository.setBudget(month: month, amount: amount);
  }
}
