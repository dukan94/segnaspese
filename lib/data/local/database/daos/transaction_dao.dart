import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/transactions_table.dart';

part 'transaction_dao.g.dart';

/// Accesso ai dati grezzi (righe Drift) della tabella [Transactions].
///
/// Il DAO non conosce le entità di dominio: restituisce sempre righe
/// [Transaction] generate da Drift (data class del table `Transactions`).
/// La conversione verso [TransactionEntity] avviene nel mapper
/// (v. data/mappers), usato da [TransactionRepositoryImpl].
@DriftAccessor(tables: [Transactions])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// Tutte le transazioni non cancellate, più recenti prima.
  Stream<List<Transaction>> watchAll() {
    final query = select(transactions)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);
    return query.watch();
  }

  /// Transazioni comprese in un intervallo di date (es. per la Home/Dashboard).
  Stream<List<Transaction>> watchByPeriod({
    required DateTime from,
    required DateTime to,
  }) {
    final query = select(transactions)
      ..where((t) =>
          t.isDeleted.equals(false) &
          t.date.isBiggerOrEqualValue(from) &
          t.date.isSmallerOrEqualValue(to))
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);
    return query.watch();
  }

  /// Ricerca full-criteria (usata dalla schermata Ricerca, M6, e riusabile
  /// già da ora per filtri semplici).
  Future<List<Transaction>> search({
    int? categoryId,
    double? amount,
    DateTime? date,
    String? note,
  }) {
    final query = select(transactions)..where((t) => t.isDeleted.equals(false));

    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    if (amount != null) {
      query.where((t) => t.amount.equals(amount));
    }
    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      query.where((t) =>
          t.date.isBiggerOrEqualValue(startOfDay) &
          t.date.isSmallerThanValue(endOfDay));
    }
    if (note != null && note.isNotEmpty) {
      query.where((t) => t.note.like('%$note%'));
    }

    query.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return query.get();
  }

  Future<Transaction?> getById(int id) {
    return (select(transactions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertTransaction(TransactionsCompanion entry) {
    return into(transactions).insert(entry);
  }

  /// Inserisce più transazioni in un'unica operazione atomica (usato
  /// dall'import): o vanno a buon fine tutte, o nessuna. [batch] esegue gli
  /// insert dentro una singola transazione DB e notifica i `watch()` una
  /// sola volta al termine.
  Future<void> insertAll(List<TransactionsCompanion> entries) async {
    await batch((b) => b.insertAll(transactions, entries));
  }

  Future<bool> updateTransaction(TransactionsCompanion entry) {
    return update(transactions).replace(entry);
  }

  /// Soft delete: imposta isDeleted = true e aggiorna updatedAt, così la
  /// cancellazione può essere propagata dal futuro SyncService (M7).
  Future<int> softDelete(int id) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Elimina la riga per sempre, bypassando il soft delete.
  ///
  /// Primitiva di basso livello: NON chiamarla direttamente dal pannello
  /// Admin o da un usecase. Il DAO non conosce Turso, quindi non sa se la
  /// cancellazione è già stata propagata alla sync remota — passare sempre
  /// da [SafeTransactionDeletionService], che verifica sul server prima di
  /// chiamare questo metodo (altrimenti la transazione può ricomparire da un
  /// altro dispositivo alla sync successiva).
  Future<int> hardDelete(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  /// Id di tutte le transazioni già soft-deleted, per il controllo riga per
  /// riga di [SafeTransactionDeletionService] prima della pulizia bulk
  /// ("Pulisci database" in Admin) — niente `DELETE` bulk qui: ogni riga va
  /// verificata sul server individualmente prima di eliminarla per sempre.
  Future<List<int>> getSoftDeletedIds() {
    return (select(transactions)..where((t) => t.isDeleted.equals(true)))
        .map((row) => row.id)
        .get();
  }
}
