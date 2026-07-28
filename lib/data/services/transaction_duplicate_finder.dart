import 'package:drift/drift.dart';

import '../local/database/app_database.dart';
import '../local/database/tables/categories_table.dart';

/// Cerca una transazione locale attiva, con un `syncId` diverso da
/// [excludeSyncId], che coincide per data/importo/tipo/categoria/
/// sottocategoria/rimborso/nota con i valori passati.
///
/// Usata da `TursoSyncService._pullTransactions` per riconoscere, al momento
/// del pull, un movimento arrivato da un altro dispositivo che è in realtà lo
/// stesso movimento reale già presente localmente sotto un `syncId` diverso
/// (es. importato indipendentemente su due device prima che la sync
/// funzionasse). Match esatto su tutti i campi per minimizzare i falsi
/// positivi: due spese realmente distinte ma identiche per coincidenza
/// (stesso giorno, stesso importo, stessa categoria/nota) sono rare ma
/// possibili, e qui non c'è possibilità di revisione umana prima della
/// cancellazione — a differenza dei doppioni di tassonomia di default
/// (v. dedupe_default_taxonomy.dart), dove "stesso nome" implica sempre
/// "stessa entità logica".
Future<Transaction?> findContentDuplicateTransaction(
  AppDatabase db, {
  required DateTime date,
  required double amount,
  required TransactionKind type,
  required int categoryId,
  required int? subCategoryId,
  required bool isRefund,
  required String? note,
  required String excludeSyncId,
}) {
  final query = db.select(db.transactions)
    ..where((t) =>
        t.isDeleted.equals(false) &
        t.date.equals(date) &
        t.amount.equals(amount) &
        t.type.equalsValue(type) &
        t.categoryId.equals(categoryId) &
        t.isRefund.equals(isRefund) &
        t.syncId.isNotNull() &
        t.syncId.isNotValue(excludeSyncId))
    ..where((t) => subCategoryId == null
        ? t.subCategoryId.isNull()
        : t.subCategoryId.equals(subCategoryId))
    ..where((t) => note == null ? t.note.isNull() : t.note.equals(note));
  return query.getSingleOrNull();
}
