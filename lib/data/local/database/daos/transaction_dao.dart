import 'package:drift/drift.dart';

import '../../../../domain/services/money_rounding.dart';
import '../app_database.dart';
import '../tables/transactions_table.dart';

part 'transaction_dao.g.dart';

/// Esegue l'escape dei metacaratteri jolly di SQL LIKE (`%`, `_`) e del
/// carattere di escape stesso, così una ricerca testuale può contenere
/// questi caratteri alla lettera invece di essere interpretata come
/// pattern — va sempre usato insieme a `like(..., escapeChar: r'\')`.
String _escapeLikePattern(String input) {
  return input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}

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
  }) async {
    final query = select(transactions)..where((t) => t.isDeleted.equals(false));

    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      query.where((t) =>
          t.date.isBiggerOrEqualValue(startOfDay) &
          t.date.isSmallerThanValue(endOfDay));
    }
    if (note != null && note.isNotEmpty) {
      // Escape dei caratteri jolly SQL (% e _) prima di incorniciare con i
      // "%" veri della ricerca: senza questo, una nota che contiene uno di
      // questi caratteri alla lettera (comune nelle causali bancarie, es.
      // "50%_SCONTO") verrebbe interpretata come pattern invece che come
      // testo letterale.
      query.where((t) => t.note.like('%${_escapeLikePattern(note)}%', escapeChar: r'\'));
    }

    query.orderBy([(t) => OrderingTerm.desc(t.date)]);
    final results = await query.get();
    if (amount == null) return results;
    // Confronto sull'importo arrotondato al centesimo, non uguaglianza
    // esatta su double: due importi visivamente identici possono differire
    // per rumore di rappresentazione binaria (stesso principio di
    // transaction_duplicate_finder.dart), altrimenti l'avviso "possibile
    // doppione" in "Nuova Operazione" non scatterebbe per un doppione reale.
    final roundedAmount = roundToCents(amount);
    return results.where((t) => roundToCents(t.amount) == roundedAmount).toList();
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
