import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/categories_table.dart';
import '../../domain/entities/transaction_entity.dart';
import '../home/home_providers.dart';

/// Tabelle di lookup che servono per mostrare una transazione (M59):
/// categoria, nome sottocategoria, spesa collegata a un rimborso e rimborsi
/// collegati a una spesa. Calcolate una sola volta in [transactionLookupsProvider]
/// e condivise da riga elenco (Home + Storico) e pagina di dettaglio, invece
/// di ricostruirle in ogni pagina come prima.
class TransactionLookups {
  const TransactionLookups({
    required this.categoriesById,
    required this.subCategoryNamesById,
    required this.transactionsById,
    required this.refundsByExpenseId,
  });

  final Map<int, Category> categoriesById;
  final Map<int, String> subCategoryNamesById;
  final Map<int, TransactionEntity> transactionsById;

  /// Spesa → rimborsi collegati (una spesa può averne più di uno, M25).
  final Map<int, List<TransactionEntity>> refundsByExpenseId;

  Category? categoryOf(TransactionEntity tx) => categoriesById[tx.categoryId];

  String? subCategoryNameOf(TransactionEntity tx) =>
      tx.subCategoryId != null ? subCategoryNamesById[tx.subCategoryId] : null;

  /// Spesa originale di un rimborso collegato, se presente.
  TransactionEntity? linkedExpenseOf(TransactionEntity tx) =>
      tx.refundOfId != null ? transactionsById[tx.refundOfId] : null;

  /// Rimborsi collegati a questa spesa (lista vuota se nessuno).
  List<TransactionEntity> linkedRefundsOf(TransactionEntity tx) =>
      tx.id != null ? (refundsByExpenseId[tx.id] ?? const []) : const [];
}

final transactionLookupsProvider = Provider<TransactionLookups>((ref) {
  final categories = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
  final expenseSubs = ref
          .watch(subCategoriesForTypeProvider(TransactionKind.expense))
          .valueOrNull ??
      const [];
  final incomeSubs = ref
          .watch(subCategoriesForTypeProvider(TransactionKind.income))
          .valueOrNull ??
      const [];
  final transactions =
      ref.watch(allTransactionsProvider).valueOrNull ?? const [];

  final refundsByExpenseId = <int, List<TransactionEntity>>{};
  for (final t in transactions) {
    final expenseId = t.refundOfId;
    if (expenseId != null) {
      refundsByExpenseId.putIfAbsent(expenseId, () => []).add(t);
    }
  }

  return TransactionLookups(
    categoriesById: {for (final c in categories) c.id: c},
    subCategoryNamesById: {
      for (final s in [...expenseSubs, ...incomeSubs])
        s.subCategory.id: s.subCategory.name,
    },
    transactionsById: {
      for (final t in transactions)
        if (t.id != null) t.id!: t,
    },
    refundsByExpenseId: refundsByExpenseId,
  );
});
