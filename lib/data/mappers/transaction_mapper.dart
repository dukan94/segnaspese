import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/transaction_entity.dart';
import '../local/database/app_database.dart';
import '../local/database/tables/categories_table.dart';

/// Conversioni tra la riga Drift ([Transaction]/[TransactionsCompanion])
/// e l'entità di dominio ([TransactionEntity]), incluso il mapping fra
/// l'enum Drift [TransactionKind] e l'enum di dominio [TransactionType].
extension TransactionDataMapper on Transaction {
  TransactionEntity toEntity() {
    return TransactionEntity(
      id: id,
      date: date,
      amount: amount,
      type: type.toDomain(),
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      merchantId: merchantId,
      note: note,
      receiptImagePath: receiptImagePath,
      recurringId: recurringId,
      refundOfId: refundOfId,
      isExtraordinary: isExtraordinary,
      isRefund: isRefund,
    );
  }
}

extension TransactionEntityMapper on TransactionEntity {
  /// Companion da usare per un INSERT (id assente/auto-generato).
  TransactionsCompanion toInsertCompanion() {
    return TransactionsCompanion.insert(
      date: date,
      amount: amount,
      type: type.toDrift(),
      categoryId: categoryId,
      subCategoryId: Value(subCategoryId),
      merchantId: Value(merchantId),
      note: Value(note),
      receiptImagePath: Value(receiptImagePath),
      recurringId: Value(recurringId),
      refundOfId: Value(refundOfId),
      isExtraordinary: Value(isExtraordinary),
      isRefund: Value(isRefund),
      updatedAt: Value(DateTime.now()),
      syncId: Value(const Uuid().v4()),
    );
  }

  /// Companion da usare per un UPDATE (richiede id valorizzato).
  TransactionsCompanion toUpdateCompanion() {
    assert(id != null, 'id richiesto per aggiornare una transazione esistente');
    return TransactionsCompanion(
      id: Value(id!),
      date: Value(date),
      amount: Value(amount),
      type: Value(type.toDrift()),
      categoryId: Value(categoryId),
      subCategoryId: Value(subCategoryId),
      merchantId: Value(merchantId),
      note: Value(note),
      receiptImagePath: Value(receiptImagePath),
      recurringId: Value(recurringId),
      refundOfId: Value(refundOfId),
      isExtraordinary: Value(isExtraordinary),
      isRefund: Value(isRefund),
      updatedAt: Value(DateTime.now()),
    );
  }
}

extension TransactionKindMapper on TransactionKind {
  TransactionType toDomain() {
    switch (this) {
      case TransactionKind.income:
        return TransactionType.income;
      case TransactionKind.expense:
        return TransactionType.expense;
    }
  }
}

extension TransactionTypeMapper on TransactionType {
  TransactionKind toDrift() {
    switch (this) {
      case TransactionType.income:
        return TransactionKind.income;
      case TransactionType.expense:
        return TransactionKind.expense;
    }
  }
}
