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
///
/// Se i candidati locali sono 2 o più (storico già duplicato PRIMA che
/// esistesse questa logica, es. stesso CSV importato indipendentemente su
/// più device: caso reale, non solo teorico — v. memoria
/// `project_transaction_duplicates_pre_sync`), non c'è modo di scegliere
/// quale sia "il duplicato giusto" da segnare cancellato senza rischiare di
/// eliminare la riga sbagliata: meglio non riconoscerlo come duplicato
/// (torna null, la riga arrivata dal pull viene inserita come nuova) che
/// lanciare un'eccezione che blocca l'intero pull di TUTTE le transazioni
/// (bug reale del 31 lug 2026: `getSingleOrNull()` lanciava "Bad state: Too
/// many elements" non appena incontrava il primo gruppo con 2+ candidati).
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
}) async {
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
  final matches = await query.get();
  return matches.length == 1 ? matches.single : null;
}
