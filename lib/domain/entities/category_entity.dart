import 'transaction_entity.dart';

class CategoryEntity {
  final int? id;
  final String name;
  final String icon;
  final TransactionType type;
  final int color;
  final bool isDefault;

  const CategoryEntity({
    this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.color,
    this.isDefault = false,
  });
}

class SubCategoryEntity {
  final int? id;
  final int categoryId;
  final String name;
  final String icon;

  const SubCategoryEntity({
    this.id,
    required this.categoryId,
    required this.name,
    this.icon = '',
  });
}

/// Quante righe verrebbero spostate unendo una categoria/sottocategoria in
/// un'altra (per il dialog di conferma prima del merge). [budgets] resta
/// sempre 0 per il merge di una sottocategoria: i Budget sono legati solo
/// alla categoria, non hanno una sottocategoria propria.
class CategoryMergeImpact {
  final int transactions;
  final int merchantRules;
  final int budgets;
  final int recurringTransactions;

  const CategoryMergeImpact({
    required this.transactions,
    required this.merchantRules,
    required this.budgets,
    required this.recurringTransactions,
  });

  int get total => transactions + merchantRules + budgets + recurringTransactions;
}
