import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/budget_providers.dart';
import '../../core/di/category_providers.dart';
import '../../core/di/settings_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/categories_table.dart';
import '../../domain/entities/transaction_entity.dart';

// ---------------------------------------------------------------------------
// Spese aggregate (sorgente per il confronto budget vs speso reale)
// ---------------------------------------------------------------------------

/// Parametri (anno + inclusione straordinarie) per gli aggregati annuali del
/// Budget: così il toggle "Includi straordinarie" influenza anche le barre
/// "speso" dei mesi, non solo la card di riepilogo.
typedef YearExpensesParams = ({int year, bool includeExtra});

/// Uscite dell'anno raggruppate per mese (1..12). Alimenta la pagina Budget
/// (barra speso di ogni mese). Le spese straordinarie sono escluse a meno che
/// [YearExpensesParams.includeExtra] non sia true (coerente con la Dashboard).
final yearExpensesByMonthProvider =
    StreamProvider.autoDispose.family<Map<int, double>, YearExpensesParams>((ref, params) {
  final from = DateTime(params.year, 1, 1);
  final to =
      DateTime(params.year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
  return ref
      .watch(transactionRepositoryProvider)
      .watchByPeriod(from: from, to: to)
      .map((list) {
    final map = <int, double>{};
    for (final t in list) {
      if (t.isExtraordinary && !params.includeExtra) continue;
      if (t.type == TransactionType.expense) {
        map[t.date.month] = (map[t.date.month] ?? 0) + t.netExpense;
      }
    }
    return map;
  });
});

/// Uscite di un mese raggruppate per categoria. Alimenta il dettaglio mese e
/// il riepilogo Home.
final monthExpensesByCategoryProvider =
    StreamProvider.autoDispose.family<Map<int, double>, MonthKey>((ref, key) {
  final from = key.firstDay;
  final to = DateTime(key.year, key.month + 1, 1)
      .subtract(const Duration(milliseconds: 1));
  return ref
      .watch(transactionRepositoryProvider)
      .watchByPeriod(from: from, to: to)
      .map((list) {
    final map = <int, double>{};
    for (final t in list) {
      if (t.type == TransactionType.expense) {
        map[t.categoryId] = (map[t.categoryId] ?? 0) + t.netExpense;
      }
    }
    return map;
  });
});

// ---------------------------------------------------------------------------
// View model: panoramica anno
// ---------------------------------------------------------------------------

/// Riepilogo di un mese nella vista annuale.
class MonthBudgetOverview {
  const MonthBudgetOverview({
    required this.year,
    required this.month,
    required this.total,
    required this.spent,
    required this.hasCategoryBudgets,
  });

  final int year;
  final int month;

  /// Budget totale del mese; null se non ancora impostato.
  final double? total;
  final double spent;

  /// true se il totale è stato suddiviso in almeno una categoria.
  final bool hasCategoryBudgets;

  bool get hasTotal => total != null;

  double get remaining => (total ?? 0) - spent;

  double get usedPct =>
      (total == null || total == 0) ? 0 : (spent / total!).clamp(0, 999);

  bool get isOverBudget => total != null && spent > total!;
}

/// Panoramica dei 12 mesi dell'anno: totale impostato, speso reale e se il
/// mese è già suddiviso in categorie.
final yearOverviewProvider =
    Provider.autoDispose.family<AsyncValue<List<MonthBudgetOverview>>, YearExpensesParams>((ref, params) {
  final budgets = ref.watch(budgetsForYearProvider(params.year));
  final expenses = ref.watch(yearExpensesByMonthProvider(params));

  return _combine2(budgets, expenses, (budgetList, expByMonth) {
    final totalByMonth = <int, double>{};
    final hasCatByMonth = <int, bool>{};
    for (final b in budgetList) {
      final m = b.startDate.month;
      if (b.categoryId == null) {
        totalByMonth[m] = b.amount;
      } else {
        hasCatByMonth[m] = true;
      }
    }
    return [
      for (var m = 1; m <= 12; m++)
        MonthBudgetOverview(
          year: params.year,
          month: m,
          total: totalByMonth[m],
          spent: expByMonth[m] ?? 0,
          hasCategoryBudgets: hasCatByMonth[m] ?? false,
        ),
    ];
  });
});

// ---------------------------------------------------------------------------
// View model: dettaglio mese
// ---------------------------------------------------------------------------

/// Riga di una categoria nel dettaglio mese: allocazione pianificata + speso.
class CategoryBudgetLine {
  const CategoryBudgetLine({
    required this.category,
    required this.budgetId,
    required this.allocation,
    required this.spent,
  });

  final Category category;

  /// id della riga budget di questa categoria in questo mese (per la
  /// rimozione); null se non ancora allocata.
  final int? budgetId;

  /// Importo allocato alla categoria; null se non ancora impostato.
  final double? allocation;
  final double spent;

  bool get hasAllocation => allocation != null;

  double get remaining => (allocation ?? 0) - spent;

  double get usedPct => (allocation == null || allocation == 0)
      ? 0
      : (spent / allocation!).clamp(0, 999);

  bool get isOverBudget => allocation != null && spent > allocation!;
}

/// Dettaglio completo del budget di un mese: totale, allocazioni per categoria
/// (tutte le categorie di uscita, anche quelle non ancora allocate) e i saldi
/// aggregati (assegnato, residuo, sforamento della ripartizione).
class MonthBudgetDetail {
  const MonthBudgetDetail({
    required this.year,
    required this.month,
    required this.totalBudgetId,
    required this.total,
    required this.lines,
  });

  final int year;
  final int month;

  /// id della riga del totale mensile (per la rimozione); null se non impostato.
  final int? totalBudgetId;

  /// Budget totale del mese; null se non impostato.
  final double? total;

  final List<CategoryBudgetLine> lines;

  bool get hasTotal => total != null;

  /// Somma delle allocazioni per categoria.
  double get allocated =>
      lines.fold<double>(0, (s, l) => s + (l.allocation ?? 0));

  /// Speso reale totale del mese (tutte le categorie).
  double get spentTotal => lines.fold<double>(0, (s, l) => s + l.spent);

  /// Quanto resta da assegnare rispetto al totale; null se il totale non è
  /// impostato. Negativo se la ripartizione ha superato il totale.
  double? get unallocated => total == null ? null : total! - allocated;

  /// La somma delle categorie ha superato il totale del mese.
  bool get isOverAllocated => total != null && allocated > total!;

  /// Almeno una categoria ha un'allocazione impostata.
  bool get hasCategoryBudgets => lines.any((l) => l.hasAllocation);
}

/// Dettaglio del mese: combina categorie di uscita, budget del mese e uscite
/// per categoria.
final monthDetailProvider =
    Provider.autoDispose.family<AsyncValue<MonthBudgetDetail>, MonthKey>((ref, key) {
  final categories =
      ref.watch(categoriesByTypeProvider(TransactionKind.expense));
  final budgets = ref.watch(budgetsForMonthProvider(key));
  final expenses = ref.watch(monthExpensesByCategoryProvider(key));

  return _combine3(categories, budgets, expenses,
      (catList, budgetList, expByCat) {
    int? totalBudgetId;
    double? total;
    final allocationByCat = <int, double>{};
    final budgetIdByCat = <int, int>{};

    for (final b in budgetList) {
      if (b.categoryId == null) {
        total = b.amount;
        totalBudgetId = b.id;
      } else {
        allocationByCat[b.categoryId!] = b.amount;
        if (b.id != null) budgetIdByCat[b.categoryId!] = b.id!;
      }
    }

    final lines = [
      for (final c in catList)
        CategoryBudgetLine(
          category: c,
          budgetId: budgetIdByCat[c.id],
          allocation: allocationByCat[c.id],
          spent: expByCat[c.id] ?? 0,
        ),
    ];

    return MonthBudgetDetail(
      year: key.year,
      month: key.month,
      totalBudgetId: totalBudgetId,
      total: total,
      lines: lines,
    );
  });
});

// ---------------------------------------------------------------------------
// View model: riepilogo Home (mese corrente)
// ---------------------------------------------------------------------------

/// Riepilogo budget per la Home: usa il totale mensile se impostato,
/// altrimenti la somma delle allocazioni per categoria ("Entrambi").
class HomeBudgetSummary {
  const HomeBudgetSummary({required this.budget, required this.spent});

  /// Budget effettivo del mese corrente; null se non ne esiste nessuno.
  final double? budget;
  final double spent;

  bool get hasBudget => budget != null;

  double get remaining => (budget ?? 0) - spent;

  double get usedPct =>
      (budget == null || budget == 0) ? 0 : (spent / budget!).clamp(0, 999);

  bool get isOverBudget => budget != null && spent > budget!;
}

final homeBudgetSummaryProvider =
    Provider.autoDispose<AsyncValue<HomeBudgetSummary>>((ref) {
  final key = MonthKey.of(DateTime.now());
  final budgets = ref.watch(budgetsForMonthProvider(key));
  final expenses = ref.watch(monthExpensesByCategoryProvider(key));

  return _combine2(budgets, expenses, (budgetList, expByCat) {
    double? total;
    var categorySum = 0.0;
    for (final b in budgetList) {
      if (b.categoryId == null) {
        total = b.amount;
      } else {
        categorySum += b.amount;
      }
    }
    final effective = total ?? (categorySum > 0 ? categorySum : null);
    final spent = expByCat.values.fold<double>(0, (s, v) => s + v);
    return HomeBudgetSummary(budget: effective, spent: spent);
  });
});

// ---------------------------------------------------------------------------
// View model: riepilogo e previsione annuale (obiettivo di risparmio)
// ---------------------------------------------------------------------------

/// Esito della previsione rispetto all'obiettivo di risparmio.
enum ForecastStatus { onTrack, near, off }

/// Parametri: anno + inclusione delle operazioni straordinarie.
typedef ForecastParams = ({int year, bool includeExtra});

/// Riepilogo annuale allineato al foglio Excel dell'utente.
///
/// - Reddito = solo stipendio (sottocategoria "Stipendio"; con le straordinarie
///   attive include anche le voci "Stipendio ..." come lo stipendio extra).
/// - Proiezione del reddito: reddito / numero di stipendi ricevuti × 12.
/// - Proiezione delle spese: spese / giorni trascorsi × 365.
/// - Media mensile spese: spese / giorni trascorsi × 30.
/// Per anni passati mostra i valori effettivi (nessuna proiezione).
class AnnualForecast {
  const AnnualForecast({
    required this.year,
    required this.daysElapsed,
    required this.isProjected,
    required this.incomeYtd,
    required this.expenseYtd,
    required this.salaryCount,
    required this.incomeForecast,
    required this.expenseForecast,
    required this.monthlyExpenseAvg,
    required this.goal,
  });

  final int year;
  final int daysElapsed;

  /// true se i valori "previsti" sono una proiezione (anno in corso).
  final bool isProjected;

  /// "Reddito" = solo stipendio (come nel foglio Excel), da inizio anno.
  final double incomeYtd;
  final double expenseYtd;

  /// Numero di stipendi (base) ricevuti: base della proiezione del reddito.
  final int salaryCount;

  final double incomeForecast;
  final double expenseForecast;
  final double monthlyExpenseAvg;

  /// Obiettivo di risparmio annuo; null se non impostato.
  final double? goal;

  double get savingsYtd => incomeYtd - expenseYtd;
  double get savingsForecast => incomeForecast - expenseForecast;

  /// Quanto si può spendere al mese lasciando da parte l'obiettivo:
  /// (entrate previste − obiettivo) / 12. null se manca l'obiettivo.
  double? get allowedMonthlySpend =>
      goal == null ? null : (incomeForecast - goal!) / 12;

  /// Margine tra quanto si potrebbe spendere e la spesa media attuale.
  double? get delta =>
      allowedMonthlySpend == null ? null : allowedMonthlySpend! - monthlyExpenseAvg;

  ForecastStatus? get status {
    if (goal == null) return null;
    final s = savingsForecast;
    if (s >= goal!) return ForecastStatus.onTrack;
    if (s >= goal! - 100) return ForecastStatus.near;
    return ForecastStatus.off;
  }
}

final annualForecastProvider =
    Provider.autoDispose.family<AsyncValue<AnnualForecast>, ForecastParams>((ref, params) {
  final transactions = ref.watch(yearTransactionsProvider(params.year));
  final goal = ref.watch(annualSavingsGoalProvider);
  final incomeSubs =
      ref.watch(subCategoriesForTypeProvider(TransactionKind.income));

  // Combinazione a 3 sorgenti.
  for (final v in [transactions, goal, incomeSubs]) {
    if (v.hasError) {
      return AsyncError<AnnualForecast>(
          v.error!, v.stackTrace ?? StackTrace.current);
    }
  }
  if (!(transactions.hasValue && goal.hasValue && incomeSubs.hasValue)) {
    return const AsyncLoading();
  }

  final txns = transactions.requireValue;
  final goalValue = goal.requireValue;
  final subs = incomeSubs.requireValue;

  // Sottocategorie "stipendio": base (== "stipendio") ed estese (iniziano per
  // "stipendio", es. "Stipendio Extra"), come il wildcard del foglio Excel.
  final baseSalaryIds = <int>{};
  final anySalaryIds = <int>{};
  for (final s in subs) {
    final n = s.subCategory.name.trim().toLowerCase();
    if (n == 'stipendio') baseSalaryIds.add(s.subCategory.id);
    if (n.startsWith('stipendio')) anySalaryIds.add(s.subCategory.id);
  }
  final salaryIds = params.includeExtra ? anySalaryIds : baseSalaryIds;

  final now = DateTime.now();
  const daysInYear = 365;
  final int daysElapsed;
  final bool isProjected;
  if (params.year == now.year) {
    // Come nel foglio: OGGI() − 1° gennaio (senza +1).
    daysElapsed = now.difference(DateTime(params.year, 1, 1)).inDays;
    isProjected = true;
  } else if (params.year < now.year) {
    daysElapsed = daysInYear; // anno concluso
    isProjected = false;
  } else {
    daysElapsed = 0; // anno futuro
    isProjected = false;
  }

  var incomeYtd = 0.0; // reddito = solo stipendio
  var expenseYtd = 0.0;
  var salaryCount = 0;
  for (final t in txns) {
    if (t.isExtraordinary && !params.includeExtra) continue;
    if (t.type == TransactionType.income) {
      final sub = t.subCategoryId;
      if (sub != null && salaryIds.contains(sub)) incomeYtd += t.amount;
      if (sub != null && baseSalaryIds.contains(sub)) salaryCount++;
    } else {
      expenseYtd += t.netExpense;
    }
  }

  final incomeForecast = (isProjected && salaryCount > 0)
      ? incomeYtd / salaryCount * 12
      : incomeYtd;
  final expenseForecast = (isProjected && daysElapsed > 0)
      ? expenseYtd / daysElapsed * daysInYear
      : expenseYtd;
  final monthlyExpenseAvg =
      daysElapsed > 0 ? expenseYtd / daysElapsed * 30 : 0.0;

  return AsyncData<AnnualForecast>(AnnualForecast(
    year: params.year,
    daysElapsed: daysElapsed,
    isProjected: isProjected,
    incomeYtd: incomeYtd,
    expenseYtd: expenseYtd,
    salaryCount: salaryCount,
    incomeForecast: incomeForecast,
    expenseForecast: expenseForecast,
    monthlyExpenseAvg: monthlyExpenseAvg,
    goal: goalValue,
  ));
});

// ---------------------------------------------------------------------------
// Helper: combinazione di AsyncValue
// ---------------------------------------------------------------------------

AsyncValue<R> _combine2<A, B, R>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  R Function(A, B) build,
) {
  if (a.hasError) return AsyncError<R>(a.error!, a.stackTrace ?? StackTrace.current);
  if (b.hasError) return AsyncError<R>(b.error!, b.stackTrace ?? StackTrace.current);
  if (a.hasValue && b.hasValue) {
    return AsyncData<R>(build(a.requireValue, b.requireValue));
  }
  return const AsyncLoading();
}

AsyncValue<R> _combine3<A, B, C, R>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  AsyncValue<C> c,
  R Function(A, B, C) build,
) {
  if (a.hasError) return AsyncError<R>(a.error!, a.stackTrace ?? StackTrace.current);
  if (b.hasError) return AsyncError<R>(b.error!, b.stackTrace ?? StackTrace.current);
  if (c.hasError) return AsyncError<R>(c.error!, c.stackTrace ?? StackTrace.current);
  if (a.hasValue && b.hasValue && c.hasValue) {
    return AsyncData<R>(build(a.requireValue, b.requireValue, c.requireValue));
  }
  return const AsyncLoading();
}
