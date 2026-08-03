import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/recurring_entity.dart';
import '../local/database/app_database.dart';
import '../local/database/tables/recurring_table.dart';
import 'transaction_mapper.dart';

/// Conversioni tra la riga Drift [RecurringTransaction]/
/// [RecurringTransactionsCompanion] e l'entità di dominio [RecurringEntity],
/// incluso il mapping fra l'enum Drift [RecurringFrequency] e l'enum di
/// dominio [RecurringFrequencyType]. Per il tipo (income/expense) riusa i
/// mapper già definiti in transaction_mapper.dart.
extension RecurringDataMapper on RecurringTransaction {
  RecurringEntity toEntity() {
    return RecurringEntity(
      id: id,
      description: description,
      amount: amount,
      type: type.toDomain(),
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      frequency: frequency.toDomain(),
      dayOfMonth: dayOfMonth,
      nextOccurrence: nextOccurrence,
      active: active,
      totalOccurrences: totalOccurrences,
      occurrencesGenerated: occurrencesGenerated,
    );
  }
}

extension RecurringEntityMapper on RecurringEntity {
  /// Companion da usare per un INSERT (id assente/auto-generato).
  RecurringTransactionsCompanion toInsertCompanion() {
    return RecurringTransactionsCompanion.insert(
      description: description,
      amount: amount,
      type: type.toDrift(),
      categoryId: categoryId,
      subCategoryId: Value(subCategoryId),
      frequency: frequency.toDrift(),
      dayOfMonth: Value(dayOfMonth),
      nextOccurrence: nextOccurrence,
      active: Value(active),
      totalOccurrences: Value(totalOccurrences),
      occurrencesGenerated: Value(occurrencesGenerated),
      updatedAt: Value(DateTime.now()),
      syncId: Value(const Uuid().v4()),
    );
  }

  /// Companion da usare per un UPDATE (richiede id valorizzato).
  RecurringTransactionsCompanion toUpdateCompanion() {
    assert(id != null, 'id richiesto per aggiornare una ricorrenza esistente');
    return RecurringTransactionsCompanion(
      id: Value(id!),
      description: Value(description),
      amount: Value(amount),
      type: Value(type.toDrift()),
      categoryId: Value(categoryId),
      subCategoryId: Value(subCategoryId),
      frequency: Value(frequency.toDrift()),
      dayOfMonth: Value(dayOfMonth),
      nextOccurrence: Value(nextOccurrence),
      active: Value(active),
      totalOccurrences: Value(totalOccurrences),
      occurrencesGenerated: Value(occurrencesGenerated),
      updatedAt: Value(DateTime.now()),
    );
  }
}

extension RecurringFrequencyMapper on RecurringFrequency {
  RecurringFrequencyType toDomain() {
    switch (this) {
      case RecurringFrequency.weekly:
        return RecurringFrequencyType.weekly;
      case RecurringFrequency.monthly:
        return RecurringFrequencyType.monthly;
      case RecurringFrequency.yearly:
        return RecurringFrequencyType.yearly;
    }
  }
}

extension RecurringFrequencyTypeMapper on RecurringFrequencyType {
  RecurringFrequency toDrift() {
    switch (this) {
      case RecurringFrequencyType.weekly:
        return RecurringFrequency.weekly;
      case RecurringFrequencyType.monthly:
        return RecurringFrequency.monthly;
      case RecurringFrequencyType.yearly:
        return RecurringFrequency.yearly;
    }
  }
}
