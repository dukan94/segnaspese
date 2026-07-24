import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/budget_providers.dart';
import '../../core/di/category_providers.dart';
import '../../core/di/transaction_providers.dart';
import '../../data/mappers/transaction_mapper.dart';
import '../../domain/entities/transaction_entity.dart';

/// Fetta di spesa per categoria (per la torta e la legenda).
class CategorySlice {
  const CategorySlice({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int color;
  final double amount;
}

/// Fetta di spesa per sottocategoria (per le barre orizzontali).
class SubcategorySlice {
  const SubcategorySlice({
    required this.name,
    required this.icon,
    required this.amount,
  });

  final String name;
  final String icon;
  final double amount;
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

  double get savings => totalIncome - totalExpense;
  bool get isOverBudget => totalBudget > 0 && totalExpense > totalBudget;
}

/// Parametri della Dashboard: anno + se includere le operazioni straordinarie.
typedef DashboardParams = ({int year, bool includeExtra});

/// Aggregato completo per la Dashboard dell'anno.
final dashboardDataProvider =
    Provider.family<AsyncValue<DashboardData>, DashboardParams>((ref, params) {
  final transactions = ref.watch(yearTransactionsProvider(params.year));
  final budgets = ref.watch(budgetsForYearProvider(params.year));
  final categories =
      ref.watch(categoriesByTypeProvider(TransactionType.expense.toDrift()));
  final subcats =
      ref.watch(subCategoriesForTypeProvider(TransactionType.expense.toDrift()));

  return _combine4(transactions, budgets, categories, subcats,
      (txns, budgetList, catList, subList) {
    // Totali entrate/uscite.
    var totalIncome = 0.0;
    var totalExpense = 0.0;
    final expenseByCategory = <int, double>{};
    final expenseBySubcat = <int, double>{};
    final monthlyExpense = List<double>.filled(12, 0);

    for (final t in txns) {
      // Escludi le straordinarie se il toggle è disattivato.
      if (t.isExtraordinary && !params.includeExtra) continue;
      if (t.type == TransactionType.income) {
        totalIncome += t.amount;
      } else {
        totalExpense += t.netExpense;
        expenseByCategory[t.categoryId] =
            (expenseByCategory[t.categoryId] ?? 0) + t.netExpense;
        if (t.subCategoryId != null) {
          expenseBySubcat[t.subCategoryId!] =
              (expenseBySubcat[t.subCategoryId!] ?? 0) + t.netExpense;
        }
        monthlyExpense[t.date.month - 1] += t.netExpense;
      }
    }

    // Budget effettivo mensile.
    final totalByMonth = <int, double>{};
    final catSumByMonth = <int, double>{};
    for (final b in budgetList) {
      final m = b.startDate.month;
      if (b.categoryId == null) {
        totalByMonth[m] = b.amount;
      } else {
        catSumByMonth[m] = (catSumByMonth[m] ?? 0) + b.amount;
      }
    }
    final monthlyBudget = [
      for (var m = 1; m <= 12; m++) totalByMonth[m] ?? (catSumByMonth[m] ?? 0),
    ];
    final totalBudget = monthlyBudget.fold<double>(0, (s, v) => s + v);

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
    );
  });
});

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
