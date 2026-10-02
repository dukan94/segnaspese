import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/daos/budget_dao.dart';
import '../../data/repositories_impl/budget_repository_impl.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../../domain/usecases/budget/delete_budget.dart';
import '../../domain/usecases/budget/set_category_budget.dart';
import '../../domain/usecases/budget/set_monthly_budget.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

/// Logga un fallimento della sync scatenata dopo un salvataggio (M56) —
/// stesso pattern fire-and-forget di `transaction_providers.dart` (M32),
/// mai mostrato all'utente.
void _logPostSaveSyncError(Object error, StackTrace stackTrace) {
  debugPrint('Sync Turso fallita (dopo salvataggio budget): $error\n$stackTrace');
}

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
    StreamProvider.autoDispose.family<List<BudgetEntity>, int>((ref, year) {
  return ref.watch(budgetRepositoryProvider).watchYear(year);
});

/// Tutti i budget di un singolo mese (totale + categorie).
final budgetsForMonthProvider =
    StreamProvider.autoDispose.family<List<BudgetEntity>, MonthKey>((ref, key) {
  return ref.watch(budgetRepositoryProvider).watchMonth(key.firstDay);
});

// --- Scrittura (usecase) ---

/// M56: dopo il salvataggio locale, lancia anche una sync Turso in
/// background — stesso trattamento di `addTransactionProvider`/
/// `updateTransactionProvider` (M32), mancante qui da sempre (non una
/// regressione): un budget impostato e chiuso subito dopo l'app poteva
/// restare intrappolato sul dispositivo fino al prossimo trigger
/// periodico/di stato.
final setMonthlyBudgetProvider =
    Provider<Future<void> Function({required DateTime month, required double amount})>(
        (ref) {
  final useCase = SetMonthlyBudget(ref.watch(budgetRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return ({required month, required amount}) async {
    await useCase.call(month: month, amount: amount);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M56: v. [setMonthlyBudgetProvider].
final setCategoryBudgetProvider = Provider<
    Future<void> Function({
      required int categoryId,
      required DateTime month,
      required double amount,
    })>((ref) {
  final useCase = SetCategoryBudget(ref.watch(budgetRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return ({required categoryId, required month, required amount}) async {
    await useCase.call(categoryId: categoryId, month: month, amount: amount);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M56: v. [setMonthlyBudgetProvider].
final deleteBudgetProvider = Provider<Future<void> Function(int)>((ref) {
  final useCase = DeleteBudget(ref.watch(budgetRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (id) async {
    await useCase.call(id);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});
