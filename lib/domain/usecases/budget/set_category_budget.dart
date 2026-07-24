import '../../repositories/budget_repository.dart';

/// Imposta l'allocazione di budget di una categoria dentro un mese (la
/// "suddivisione" del totale mensile). Lo sforamento è consentito: la somma
/// delle categorie può superare il totale del mese.
class SetCategoryBudget {
  SetCategoryBudget(this._repository);

  final BudgetRepository _repository;

  Future<void> call({
    required int categoryId,
    required DateTime month,
    required double amount,
  }) {
    return _repository.setBudget(
      categoryId: categoryId,
      month: month,
      amount: amount,
    );
  }
}
