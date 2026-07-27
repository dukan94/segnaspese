import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/recurring_table.dart';
import '../tables/transactions_table.dart';

part 'recurring_dao.g.dart';

/// Accesso ai dati grezzi (righe Drift) della tabella [RecurringTransactions].
///
/// Oltre al CRUD, espone [generateDue]: il "job" che all'avvio dell'app crea
/// le [Transactions] dovute dalle ricorrenze attive e fa avanzare
/// `nextOccurrence`. Necessita anche della tabella [Transactions] per inserire
/// i movimenti generati, perciò entrambe sono dichiarate in [DriftAccessor].
///
/// La conversione verso [RecurringEntity] avviene nel mapper (v. data/mappers),
/// usato da RecurringRepositoryImpl.
@DriftAccessor(tables: [RecurringTransactions, Transactions])
class RecurringDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringDaoMixin {
  RecurringDao(super.db);

  /// Tutte le ricorrenze non cancellate: prima le attive, poi in pausa; a
  /// parità, per prossima occorrenza crescente.
  Stream<List<RecurringTransaction>> watchAll() {
    final query = select(recurringTransactions)
      ..where((r) => r.isDeleted.equals(false))
      ..orderBy([
        (r) => OrderingTerm.desc(r.active),
        (r) => OrderingTerm.asc(r.nextOccurrence),
      ]);
    return query.watch();
  }

  Future<RecurringTransaction?> getById(int id) {
    return (select(recurringTransactions)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertRecurring(RecurringTransactionsCompanion entry) {
    return into(recurringTransactions).insert(entry);
  }

  Future<bool> updateRecurring(RecurringTransactionsCompanion entry) {
    return update(recurringTransactions).replace(entry);
  }

  /// Soft delete: imposta isDeleted = true e aggiorna updatedAt, così la
  /// cancellazione può essere propagata dal futuro SyncService (M7).
  Future<int> softDelete(int id) {
    return (update(recurringTransactions)..where((r) => r.id.equals(id))).write(
      RecurringTransactionsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mette in pausa / riattiva una ricorrenza.
  Future<int> setActive(int id, bool active) {
    return (update(recurringTransactions)..where((r) => r.id.equals(id))).write(
      RecurringTransactionsCompanion(
        active: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Genera le transazioni dovute fino a [asOf] (incluso) per tutte le
  /// ricorrenze attive, avanzando `nextOccurrence` oltre [asOf].
  ///
  /// Recupera anche eventuali occorrenze arretrate (app non aperta per più
  /// periodi). Tutto in un'unica transazione DB. Restituisce quante
  /// transazioni ha creato.
  Future<int> generateDue(DateTime asOf) async {
    // Normalizzato a mezzanotte: confronto solo per data, non per ora.
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    var generated = 0;

    await transaction(() async {
      final active = await (select(recurringTransactions)
            ..where((r) => r.isDeleted.equals(false) & r.active.equals(true)))
          .get();

      for (final r in active) {
        var next = DateTime(
          r.nextOccurrence.year,
          r.nextOccurrence.month,
          r.nextOccurrence.day,
        );
        var created = false;

        while (!next.isAfter(today)) {
          await into(transactions).insert(
            TransactionsCompanion.insert(
              date: next,
              amount: r.amount,
              type: r.type,
              categoryId: r.categoryId,
              subCategoryId: Value(r.subCategoryId),
              note: Value(r.description),
              recurringId: Value(r.id),
              updatedAt: Value(DateTime.now()),
              // Companion costruita a mano (non passa dal mapper, che di
              // norma genera il syncId): senza questo, le transazioni
              // generate dalle ricorrenze non venivano mai sincronizzate.
              syncId: Value(const Uuid().v4()),
            ),
          );
          generated++;
          created = true;
          next = _advance(next, r.frequency, r.dayOfMonth);
        }

        if (created) {
          await (update(recurringTransactions)..where((t) => t.id.equals(r.id)))
              .write(
            RecurringTransactionsCompanion(
              nextOccurrence: Value(next),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }
    });

    return generated;
  }

  /// Calcola la data della prossima occorrenza dopo [current] in base alla
  /// [frequency]. Per il mensile usa [dayOfMonth] se impostato (limitato
  /// all'ultimo giorno del mese, es. il 31 diventa 28/29/30 dove serve).
  static DateTime _advance(
    DateTime current,
    RecurringFrequency frequency,
    int? dayOfMonth,
  ) {
    switch (frequency) {
      case RecurringFrequency.weekly:
        return DateTime(current.year, current.month, current.day + 7);
      case RecurringFrequency.monthly:
        var year = current.year;
        var month = current.month + 1;
        if (month > 12) {
          month = 1;
          year++;
        }
        final targetDay = dayOfMonth ?? current.day;
        // Giorno 0 del mese successivo = ultimo giorno del mese corrente.
        final lastDay = DateTime(year, month + 1, 0).day;
        final day = targetDay > lastDay ? lastDay : targetDay;
        return DateTime(year, month, day);
      case RecurringFrequency.yearly:
        final year = current.year + 1;
        // Gestisce il 29 feb su anni non bisestili.
        final lastDay = DateTime(year, current.month + 1, 0).day;
        final day = current.day > lastDay ? lastDay : current.day;
        return DateTime(year, current.month, day);
    }
  }
}
