import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/budget_providers.dart';
import '../../core/di/category_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/daos/category_dao.dart';
import '../../data/mappers/transaction_mapper.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/transaction_entity.dart';

/// Fetta di spesa per categoria (per la torta e la legenda).
class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
    required this.count,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int color;
  final double amount;

  /// Numero di spese (esclusi i rimborsi, che non sono un'occorrenza a sé
  /// ma solo una rettifica di un'altra spesa nella stessa categoria — M33).
  final int count;

  /// Importo medio per occorrenza, già al netto dei rimborsi (es. spesa 50€
  /// + rimborso 25€ nella stessa categoria → count 1, average 25€, non
  /// (50-25)/2). 0 se [count] è 0 (mai per una fetta effettivamente mostrata:
  /// [amount] > 0 implica almeno una spesa non-rimborso).
  double get average => count == 0 ? 0 : amount / count;
}

/// Fetta di spesa per sottocategoria (per le barre orizzontali).
class SubcategorySlice {
  const SubcategorySlice({
    required this.name,
    required this.icon,
    required this.amount,
    required this.count,
  });

  final String name;
  final String icon;
  final double amount;

  /// V. [CategorySlice.count].
  final int count;

  double get average => count == 0 ? 0 : amount / count;
}

/// Dati aggregati della Dashboard per un anno.
class DashboardData {
  const DashboardData({
    required this.year,
    required this.totalIncome,
    required this.totalExpense,
    required this.totalBudget,
    required this.byCategory,
    required this.subByCategory,
    required this.monthlyExpense,
    required this.monthlyBudget,
    required this.monthlyExpenseByCategory,
    required this.monthlyBudgetByCategory,
  });

  final int year;

  final double totalIncome;
  final double totalExpense;

  /// Budget annuo = somma del budget effettivo di ogni mese (totale mensile se
  /// impostato, altrimenti somma delle allocazioni per categoria).
  final double totalBudget;

  /// Spese per categoria (decrescente), solo importi > 0.
  final List<CategorySlice> byCategory;

  /// Sottocategorie per categoria (categoryId → fette decrescenti).
  final Map<int, List<SubcategorySlice>> subByCategory;

  /// Uscite di ciascun mese (indici 0..11 = gen..dic).
  final List<double> monthlyExpense;

  /// Budget effettivo di ciascun mese (indici 0..11).
  final List<double> monthlyBudget;

  /// Come [monthlyExpense], ma per singola categoria (categoryId → 12
  /// valori) — usato da "Andamento 12 mesi" quando l'utente ha selezionato
  /// una fetta nella torta, stessa categoria del dettaglio sottocategorie.
  final Map<int, List<double>> monthlyExpenseByCategory;

  /// Come [monthlyBudget], ma solo il budget impostato specificamente per
  /// quella categoria (nessun fallback al budget totale mensile: un budget
  /// "totale" non è per definizione di una categoria).
  final Map<int, List<double>> monthlyBudgetByCategory;

  double get savings => totalIncome - totalExpense;
  bool get isOverBudget => totalBudget > 0 && totalExpense > totalBudget;
}

/// Parametri della Dashboard: anno, mese opzionale (null = intero anno) e se
/// includere le operazioni straordinarie.
typedef DashboardParams = ({int year, int? month, bool includeExtra});

/// Aggregato completo per la Dashboard dell'anno.
final dashboardDataProvider = Provider.autoDispose
    .family<AsyncValue<DashboardData>, DashboardParams>((ref, params) {
  final transactions = ref.watch(yearTransactionsProvider(params.year));
  final budgets = ref.watch(budgetsForYearProvider(params.year));
  final categories =
      ref.watch(categoriesByTypeProvider(TransactionType.expense.toDrift()));
  final subcats = ref
      .watch(subCategoriesForTypeProvider(TransactionType.expense.toDrift()));

  return _combine4(
      transactions,
      budgets,
      categories,
      subcats,
      (txns, budgetList, catList, subList) =>
          buildDashboardData(txns, budgetList, catList, subList, params));
});

/// Logica di aggregazione pura, estratta dal provider (M33) per poterla
/// testare senza passare da Riverpod/Drift — v. `test/dashboard_data_test.dart`
/// per i casi limite del conteggio/media al netto dei rimborsi.
DashboardData buildDashboardData(
  List<TransactionEntity> txns,
  List<BudgetEntity> budgetList,
  List<Category> catList,
  List<SubCategoryWithCategory> subList,
  DashboardParams params,
) {
  // Totali entrate/uscite.
  var totalIncome = 0.0;
  var totalExpense = 0.0;
  final expenseByCategory = <int, double>{};
  final expenseBySubcat = <int, double>{};
  // Conteggio occorrenze (M33): solo spese vere, non i rimborsi — un
  // rimborso non è una spesa a sé ma la rettifica di un'altra già
  // contata (v. CategorySlice.count).
  final countByCategory = <int, int>{};
  final countBySubcat = <int, int>{};
  final monthlyExpense = List<double>.filled(12, 0);
  final monthlyExpenseByCategory = <int, List<double>>{};

  for (final t in txns) {
    // Escludi le straordinarie se il toggle è disattivato.
    if (t.isExtraordinary && !params.includeExtra) continue;
    // Filtro periodo: se è impostato un mese, totali/categorie/sottocategorie
    // considerano solo quel mese; l'andamento 12 mesi resta sempre annuale.
    final inPeriod = params.month == null || t.date.month == params.month;
    if (t.type == TransactionType.income) {
      if (inPeriod) totalIncome += t.amount;
    } else {
      monthlyExpense[t.date.month - 1] += t.netExpense;
      (monthlyExpenseByCategory[t.categoryId] ??=
          List.filled(12, 0))[t.date.month - 1] += t.netExpense;
      if (inPeriod) {
        totalExpense += t.netExpense;
        expenseByCategory[t.categoryId] =
            (expenseByCategory[t.categoryId] ?? 0) + t.netExpense;
        if (!t.isRefund) {
          countByCategory[t.categoryId] =
              (countByCategory[t.categoryId] ?? 0) + 1;
        }
        if (t.subCategoryId != null) {
          expenseBySubcat[t.subCategoryId!] =
              (expenseBySubcat[t.subCategoryId!] ?? 0) + t.netExpense;
          if (!t.isRefund) {
            countBySubcat[t.subCategoryId!] =
                (countBySubcat[t.subCategoryId!] ?? 0) + 1;
          }
        }
      }
    }
  }

  // Budget effettivo mensile.
  final totalByMonth = <int, double>{};
  final catSumByMonth = <int, double>{};
  final monthlyBudgetByCategory = <int, List<double>>{};
  for (final b in budgetList) {
    final m = b.startDate.month;
    if (b.categoryId == null) {
      totalByMonth[m] = b.amount;
    } else {
      catSumByMonth[m] = (catSumByMonth[m] ?? 0) + b.amount;
      (monthlyBudgetByCategory[b.categoryId!] ??= List.filled(12, 0))[m - 1] +=
          b.amount;
    }
  }
  final monthlyBudget = [
    for (var m = 1; m <= 12; m++) totalByMonth[m] ?? (catSumByMonth[m] ?? 0),
  ];
  // Budget del periodo: nel mese selezionato è il budget di quel mese,
  // nell'intero anno è la somma dei 12 mesi.
  final totalBudget = params.month == null
      ? monthlyBudget.fold<double>(0, (s, v) => s + v)
      : monthlyBudget[params.month! - 1];

  // Fette per categoria (con nome/icona/colore), decrescente.
  final catById = {for (final c in catList) c.id: c};
  final byCategory = <CategorySlice>[
    for (final entry in expenseByCategory.entries)
      if (entry.value > 0)
        CategorySlice(
          categoryId: entry.key,
          name: catById[entry.key]?.name ?? 'Categoria',
          icon: catById[entry.key]?.icon ?? '',
          color: catById[entry.key]?.color ?? 0xFF9E9E9E,
          amount: entry.value,
          count: countByCategory[entry.key] ?? 0,
        ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  // Fette per sottocategoria, raggruppate per categoria padre.
  final subInfo = {
    for (final s in subList)
      s.subCategory.id: (
        categoryId: s.category.id,
        name: s.subCategory.name,
        icon: s.subCategory.icon,
      ),
  };
  final subByCategory = <int, List<SubcategorySlice>>{};
  for (final entry in expenseBySubcat.entries) {
    final info = subInfo[entry.key];
    if (info == null || entry.value <= 0) continue;
    subByCategory.putIfAbsent(info.categoryId, () => []).add(
          SubcategorySlice(
            name: info.name,
            icon: info.icon,
            amount: entry.value,
            count: countBySubcat[entry.key] ?? 0,
          ),
        );
  }
  for (final list in subByCategory.values) {
    list.sort((a, b) => b.amount.compareTo(a.amount));
  }

  return DashboardData(
    year: params.year,
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    totalBudget: totalBudget,
    byCategory: byCategory,
    subByCategory: subByCategory,
    monthlyExpense: monthlyExpense,
    monthlyBudget: monthlyBudget,
    monthlyExpenseByCategory: monthlyExpenseByCategory,
    monthlyBudgetByCategory: monthlyBudgetByCategory,
  );
}

// --- Helper: combinazione di 4 AsyncValue ---

AsyncValue<R> _combine4<A, B, C, D, R>(
  AsyncValue<A> a,
  AsyncValue<B> b,
  AsyncValue<C> c,
  AsyncValue<D> d,
  R Function(A, B, C, D) build,
) {
  final values = [a, b, c, d];
  for (final v in values) {
    if (v.hasError) {
      return AsyncError<R>(v.error!, v.stackTrace ?? StackTrace.current);
    }
  }
  if (a.hasValue && b.hasValue && c.hasValue && d.hasValue) {
    return AsyncData<R>(
        build(a.requireValue, b.requireValue, c.requireValue, d.requireValue));
  }
  return const AsyncLoading();
}
