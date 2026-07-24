import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/daos/budget_dao.dart';
import '../../data/repositories_impl/budget_repository_impl.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../../domain/usecases/budget/delete_budget.dart';
import '../../domain/usecases/budget/set_category_budget.dart';
import '../../domain/usecases/budget/set_monthly_budget.dart';
import 'database_provider.dart';

/// Chiave stabile (anno + mese) per le `family` legate a un mese specifico.
/// Serve un valore con `==`/`hashCode` corretti: un `DateTime` grezzo con
/// componenti orarie diverse romperebbe la cache dei provider.
class MonthKey {
  const MonthKey(this.year, this.month);

  MonthKey.of(DateTime date) : this(date.year, date.month);

  final int year;
  final int month;

  /// Primo giorno del mese, usato per interrogare i budget.
  DateTime get firstDay => DateTime(year, month, 1);

  @override
  bool operator ==(Object other) =>
      other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

final budgetDaoProvider = Provider<BudgetDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.budgetDao;
});

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return BudgetRepositoryImpl(ref.watch(budgetDaoProvider));
});

// --- Letture reattive ---

/// Tutti i budget di un anno (totali mensili + per categoria).
final budgetsForYearProvider =
    StreamProvider.family<List<BudgetEntity>, int>((ref, year) {
  return ref.watch(budgetRepositoryProvider).watchYear(year);
});

/// Tutti i budget di un singolo mese (totale + categorie).
final budgetsForMonthProvider =
    StreamProvider.family<List<BudgetEntity>, MonthKey>((ref, key) {
  return ref.watch(budgetRepositoryProvider).watchMonth(key.firstDay);
});

// --- Scrittura (usecase) ---

final setMonthlyBudgetProvider = Provider<SetMonthlyBudget>((ref) {
  return SetMonthlyBudget(ref.watch(budgetRepositoryProvider));
});

final setCategoryBudgetProvider = Provider<SetCategoryBudget>((ref) {
  return SetCategoryBudget(ref.watch(budgetRepositoryProvider));
});

final deleteBudgetProvider = Provider<DeleteBudget>((ref) {
  return DeleteBudget(ref.watch(budgetRepositoryProvider));
});
