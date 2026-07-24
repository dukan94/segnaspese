enum BudgetPeriodType { monthly, yearly }

class BudgetEntity {
  final int? id;

  /// null = budget complessivo, non legato a una categoria specifica.
  final int? categoryId;
  final BudgetPeriodType period;
  final double amount;
  final DateTime startDate;

  const BudgetEntity({
    this.id,
    this.categoryId,
    required this.period,
    required this.amount,
    required this.startDate,
  });
}

/// Risultato del calcolo "Saldo vs Budget" per un dato periodo:
/// Budget - Uscite (v. progettazione, sezione "Saldi richiesti").
class BudgetBalance {
  final double budgetAmount;
  final double spentAmount;

  const BudgetBalance({required this.budgetAmount, required this.spentAmount});

  double get remaining => budgetAmount - spentAmount;
  double get usedPercentage =>
      budgetAmount == 0 ? 0 : (spentAmount / budgetAmount).clamp(0, 999);
}

/// Risultato del calcolo "Saldo Reale": Entrate - Uscite.
class RealBalance {
  final double totalIncome;
  final double totalExpense;

  const RealBalance({required this.totalIncome, required this.totalExpense});

  double get net => totalIncome - totalExpense;
}
