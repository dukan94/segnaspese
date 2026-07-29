import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../local/database/daos/transaction_dao.dart';
import '../mappers/transaction_mapper.dart';

/// Implementazione concreta di [TransactionRepository], basata su Drift.
///
/// Converte sempre le righe grezze del [TransactionDao] in [TransactionEntity]
/// tramite il mapper, in modo che il resto dell'app (UseCase, Presentation)
/// non veda mai i tipi generati da Drift.
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._dao);

  final TransactionDao _dao;

  @override
  Stream<List<TransactionEntity>> watchAll() {
    return _dao.watchAll().map(
          (rows) => rows.map((row) => row.toEntity()).toList(),
        );
  }

  @override
  Stream<List<TransactionEntity>> watchByPeriod({
    required DateTime from,
    required DateTime to,
  }) {
    return _dao.watchByPeriod(from: from, to: to).map(
          (rows) => rows.map((row) => row.toEntity()).toList(),
        );
  }

  @override
  Future<List<TransactionEntity>> search({
    String? merchantQuery,
    String? note,
    int? categoryId,
    double? amount,
    DateTime? date,
  }) async {
    // NOTA: il filtro per negozio (merchantQuery) richiede un join con la
    // tabella Merchants, che verrà aggiunto quando il repository/DAO Merchant
    // sarà disponibile (M6 - Ricerca). Per ora viene ignorato.
    final rows = await _dao.search(
      categoryId: categoryId,
      amount: amount,
      date: date,
      note: note,
    );
    return rows.map((row) => row.toEntity()).toList();
  }

  @override
  Future<int> add(TransactionEntity transaction) {
    return _dao.insertTransaction(transaction.toInsertCompanion());
  }

  @override
  Future<void> addAll(List<TransactionEntity> transactions) {
    return _dao.insertAll(
      transactions.map((t) => t.toInsertCompanion()).toList(),
    );
  }

  @override
  Future<void> update(TransactionEntity transaction) async {
    await _dao.updateTransaction(transaction.toUpdateCompanion());
  }

  @override
  Future<void> delete(int id) async {
    await _dao.softDelete(id);
  }

  @override
  Future<void> hardDelete(int id) async {
    await _dao.hardDelete(id);
  }

  @override
  Future<int> purgeSoftDeleted() {
    return _dao.purgeSoftDeleted();
  }
}
