import '../../domain/entities/recurring_entity.dart';
import '../../domain/repositories/recurring_repository.dart';
import '../local/database/daos/recurring_dao.dart';
import '../mappers/recurring_mapper.dart';

/// Implementazione concreta di [RecurringRepository], basata su Drift.
///
/// Converte le righe grezze del [RecurringDao] in [RecurringEntity] tramite il
/// mapper, così che il resto dell'app non veda mai i tipi generati da Drift.
class RecurringRepositoryImpl implements RecurringRepository {
  RecurringRepositoryImpl(this._dao);

  final RecurringDao _dao;

  @override
  Stream<List<RecurringEntity>> watchAll() {
    return _dao
        .watchAll()
        .map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Future<int> add(RecurringEntity recurring) {
    return _dao.insertRecurring(recurring.toInsertCompanion());
  }

  @override
  Future<void> update(RecurringEntity recurring) async {
    await _dao.updateRecurring(recurring.toUpdateCompanion());
  }

  @override
  Future<void> delete(int id) async {
    await _dao.softDelete(id);
  }

  @override
  Future<void> setActive(int id, bool active) async {
    await _dao.setActive(id, active);
  }

  @override
  Future<int> generateDue(DateTime asOf) {
    return _dao.generateDue(asOf);
  }
}
