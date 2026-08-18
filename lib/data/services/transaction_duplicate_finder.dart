import 'package:drift/drift.dart';

import '../../domain/services/money_rounding.dart';
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
/// `project_transaction_duplicates_pre_sync`), la riga arrivata dal pull
/// viene comunque riconosciuta come duplicata: qui NON scegliamo quale
/// candidato locale è "quello giusto" (nessuno viene toccato/cancellato),
/// scegliamo solo se la riga remota va inserita come nuova oppure no. Con
/// 1+ candidati che combaciano su tutti i campi, il contenuto è già
/// rappresentato in locale — inserirla comunque farebbe ricrescere un
/// gruppo già duplicato invece di lasciarlo stabile (bug reale del 31 lug
/// 2026: con `getSingleOrNull()` un pull su un gruppo con 2+ candidati
/// lanciava "Bad state: Too many elements", bloccando l'intero pull di
/// TUTTE le transazioni; il fix intermedio tornava null su 2+, il che
/// evitava il crash ma faceva CRESCERE i gruppi già duplicati a ogni sync
/// tra due device, invece di lasciarli stabili — v. stessa memoria).
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
  // Confronto sull'importo arrotondato al centesimo, non uguaglianza esatta
  // su double: due righe logicamente identiche possono differire per rumore
  // di rappresentazione binaria (stesso principio di
  // statement_duplicate_matcher.dart, scritto apposta per questo). Il
  // filtro sull'importo resta in Dart, dopo la query, invece che nel WHERE
  // SQL: più semplice che replicare l'arrotondamento in SQL, e il numero di
  // righe candidate (stessa data/categoria/tipo) è comunque piccolo.
  final roundedAmount = roundToCents(amount);
  final sameAmount = matches.where((t) => roundToCents(t.amount) == roundedAmount);
  return sameAmount.isEmpty ? null : sameAmount.first;
}
