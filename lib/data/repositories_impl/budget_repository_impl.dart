import '../../domain/entities/budget_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../local/database/daos/budget_dao.dart';
import '../mappers/budget_mapper.dart';

/// Implementazione concreta di [BudgetRepository], basata su Drift.
///
/// Converte le righe grezze del [BudgetDao] in [BudgetEntity] tramite il
/// mapper, così che il resto dell'app non veda mai i tipi generati da Drift.
class BudgetRepositoryImpl implements BudgetRepository {
  BudgetRepositoryImpl(this._dao);

  final BudgetDao _dao;

  @override
  Stream<List<BudgetEntity>> watchYear(int year) {
    return _dao
        .watchByYear(year)
        .map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Stream<List<BudgetEntity>> watchMonth(DateTime month) {
    return _dao
        .watchByMonth(month)
        .map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Future<void> setBudget({
    int? categoryId,
    required DateTime month,
    required double amount,
  }) {
    return _dao.upsertMonthlyBudget(
      categoryId: categoryId,
      month: month,
      amount: amount,
    );
  }

  @override
  Future<void> deleteBudget(int id) async {
    await _dao.softDelete(id);
  }
}
