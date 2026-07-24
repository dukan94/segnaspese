import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/budgets_table.dart';

part 'budget_dao.g.dart';

/// Accesso ai dati grezzi (righe Drift) della tabella [Budgets].
///
/// Modello dei dati (deciso con l'utente):
/// - Ogni MESE dell'anno ha il proprio budget totale, impostato singolarmente:
///   riga con `categoryId == null`, `period == monthly` e `startDate` = 1° del
///   mese di riferimento.
/// - Dentro un mese, il totale può essere suddiviso tra le categorie: una riga
///   per categoria (`categoryId` valorizzato), stesso `startDate` del mese.
/// - `startDate` identifica quindi il mese a cui il budget si riferisce: ogni
///   mese conserva la propria storia (nessun valore viene mai sovrascritto da
///   modifiche ad altri mesi). Modificare lo stesso mese aggiorna la sua riga.
///
/// Nessuna modifica allo schema: la tabella `Budgets` esiste già dallo scaffold
/// M0. Lo sforamento è sempre consentito — qui si salvano solo gli importi
/// pianificati, i confronti con lo speso reale avvengono nel layer di
/// presentazione.
@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  /// Primo giorno del mese, usato come chiave temporale del budget.
  DateTime _firstDayOf(DateTime month) => DateTime(month.year, month.month, 1);

  /// Tutti i budget non cancellati di un anno (totali mensili + per categoria),
  /// ordinati per data. La suddivisione totale/categoria avviene a valle.
  Stream<List<Budget>> watchByYear(int year) {
    final from = DateTime(year, 1, 1);
    final to = DateTime(year + 1, 1, 1);
    final query = select(budgets)
      ..where((b) =>
          b.isDeleted.equals(false) &
          b.startDate.isBiggerOrEqualValue(from) &
          b.startDate.isSmallerThanValue(to))
      ..orderBy([(b) => OrderingTerm.asc(b.startDate)]);
    return query.watch();
  }

  /// Tutti i budget non cancellati di un singolo mese (totale + categorie).
  Stream<List<Budget>> watchByMonth(DateTime month) {
    final from = _firstDayOf(month);
    final to = DateTime(month.year, month.month + 1, 1);
    final query = select(budgets)
      ..where((b) =>
          b.isDeleted.equals(false) &
          b.startDate.isBiggerOrEqualValue(from) &
          b.startDate.isSmallerThanValue(to))
      ..orderBy([(b) => OrderingTerm.asc(b.startDate)]);
    return query.watch();
  }

  /// Crea o aggiorna (upsert) il budget di un mese per una categoria
  /// (`categoryId` valorizzato) o il totale del mese (`categoryId == null`).
  /// Se esiste già una riga per quella chiave (mese, categoria) ne aggiorna
  /// l'importo; altrimenti la inserisce.
  Future<void> upsertMonthlyBudget({
    int? categoryId,
    required DateTime month,
    required double amount,
  }) async {
    final from = _firstDayOf(month);
    final to = DateTime(month.year, month.month + 1, 1);

    await transaction(() async {
      final existing = await (select(budgets)
            ..where((b) =>
                b.isDeleted.equals(false) &
                b.startDate.isBiggerOrEqualValue(from) &
                b.startDate.isSmallerThanValue(to) &
                (categoryId == null
                    ? b.categoryId.isNull()
                    : b.categoryId.equals(categoryId))))
          .getSingleOrNull();

      if (existing == null) {
        await into(budgets).insert(
          BudgetsCompanion.insert(
            categoryId: Value(categoryId),
            period: BudgetPeriod.monthly,
            amount: amount,
            startDate: from,
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await (update(budgets)..where((b) => b.id.equals(existing.id))).write(
          BudgetsCompanion(
            amount: Value(amount),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// Soft delete di un budget (es. rimozione dell'allocazione di una categoria
  /// o azzeramento del totale di un mese), coerente con la sync futura (M7).
  Future<int> softDelete(int id) {
    return (update(budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
