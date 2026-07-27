import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/budget_entity.dart';
import '../local/database/app_database.dart';
import '../local/database/tables/budgets_table.dart';

/// Conversioni tra la riga Drift [Budget]/[BudgetsCompanion] e l'entità di
/// dominio [BudgetEntity], incluso il mapping fra l'enum Drift [BudgetPeriod]
/// e l'enum di dominio [BudgetPeriodType].
extension BudgetDataMapper on Budget {
  BudgetEntity toEntity() {
    return BudgetEntity(
      id: id,
      categoryId: categoryId,
      period: period.toDomain(),
      amount: amount,
      startDate: startDate,
    );
  }
}

extension BudgetEntityMapper on BudgetEntity {
  BudgetsCompanion toInsertCompanion() {
    return BudgetsCompanion.insert(
      categoryId: Value(categoryId),
      period: period.toDrift(),
      amount: amount,
      startDate: startDate,
      updatedAt: Value(DateTime.now()),
      syncId: Value(const Uuid().v4()),
    );
  }

  BudgetsCompanion toUpdateCompanion() {
    assert(id != null, 'id richiesto per aggiornare un budget esistente');
    return BudgetsCompanion(
      id: Value(id!),
      categoryId: Value(categoryId),
      period: Value(period.toDrift()),
      amount: Value(amount),
      startDate: Value(startDate),
      updatedAt: Value(DateTime.now()),
    );
  }
}

extension BudgetPeriodMapper on BudgetPeriod {
  BudgetPeriodType toDomain() {
    switch (this) {
      case BudgetPeriod.monthly:
        return BudgetPeriodType.monthly;
      case BudgetPeriod.yearly:
        return BudgetPeriodType.yearly;
    }
  }
}

extension BudgetPeriodTypeMapper on BudgetPeriodType {
  BudgetPeriod toDrift() {
    switch (this) {
      case BudgetPeriodType.monthly:
        return BudgetPeriod.monthly;
      case BudgetPeriodType.yearly:
        return BudgetPeriod.yearly;
    }
  }
}
