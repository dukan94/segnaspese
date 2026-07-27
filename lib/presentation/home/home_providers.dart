import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/transaction_providers.dart';
import '../../domain/entities/transaction_entity.dart';

/// Riepilogo del mese corrente: entrate, uscite e saldo del periodo.
class MonthlySummary {
  const MonthlySummary({
    required this.income,
    required this.expense,
  });

  final double income;
  final double expense;

  double get balance => income - expense;

  static const empty = MonthlySummary(income: 0, expense: 0);
}

/// Tutte le transazioni, più recenti prima (usato sia per il saldo reale
/// "di sempre" sia come sorgente per le "Ultime operazioni").
final allTransactionsProvider = StreamProvider<List<TransactionEntity>>((ref) {
  return ref.watch(transactionRepositoryProvider).watchAll();
});

/// Transazioni del mese corrente (per il calcolo di [MonthlySummary]).
final currentMonthTransactionsProvider =
    StreamProvider<List<TransactionEntity>>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, 1);
  final to = DateTime(now.year, now.month + 1, 1)
      .subtract(const Duration(milliseconds: 1));
  return ref.watch(transactionRepositoryProvider).watchByPeriod(
        from: from,
        to: to,
      );
});

final monthlySummaryProvider = Provider<AsyncValue<MonthlySummary>>((ref) {
  final transactions = ref.watch(currentMonthTransactionsProvider);
  return transactions.whenData((list) {
    var income = 0.0;
    var expense = 0.0;
    for (final t in list) {
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else {
        expense += t.netExpense;
      }
    }
    return MonthlySummary(income: income, expense: expense);
  });
});

/// Transazioni dell'anno corrente (per il saldo annuale della Home, mostrato
/// con meno enfasi rispetto al saldo del mese).
final currentYearTransactionsProvider =
    StreamProvider<List<TransactionEntity>>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, 1, 1);
  final to =
      DateTime(now.year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
  return ref.watch(transactionRepositoryProvider).watchByPeriod(
        from: from,
        to: to,
      );
});

/// Saldo dell'anno corrente: entrate meno uscite nette (rimborsi già
/// sottratti, come in [monthlySummaryProvider]), da inizio anno a oggi.
final yearlyBalanceProvider = Provider<AsyncValue<double>>((ref) {
  final transactions = ref.watch(currentYearTransactionsProvider);
  return transactions.whenData((list) {
    var balance = 0.0;
    for (final t in list) {
      balance += t.type == TransactionType.income ? t.amount : -t.netExpense;
    }
    return balance;
  });
});

/// Ultime N operazioni per la Home (la lista è già ordinata per data
/// decrescente dal DAO).
final recentTransactionsProvider = Provider<AsyncValue<List<TransactionEntity>>>((ref) {
  final transactions = ref.watch(allTransactionsProvider);
  return transactions.whenData((list) => list.take(5).toList());
});
