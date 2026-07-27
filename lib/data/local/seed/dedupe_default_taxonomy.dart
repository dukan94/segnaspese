import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Ripara i doppioni di categorie/sottocategorie/regole di default (e i
/// budget che ne conseguono) creati quando due dispositivi hanno seedato la
/// tassonomia indipendentemente, prima che esistesse la sync multi-dispositivo
/// (v. default_categories_seed.dart per il fix alla radice: syncId
/// deterministico per le nuove installazioni, cosi' non succede piu').
///
/// Per ogni gruppo di righe duplicate (stesso contenuto logico, non
/// cancellate) tiene quella con il `syncId` più basso in ordine alfabetico —
/// regola deterministica: due dispositivi che vedono lo stesso insieme di
/// duplicati (dopo essersi sincronizzati) scelgono sempre lo stesso
/// sopravvissuto senza bisogno di coordinarsi tra loro. Le altre righe
/// vengono ripuntate (chi le referenziava passa al sopravvissuto) e poi
/// nascoste (soft delete, **mai** una cancellazione reale): alla sync
/// successiva la cancellazione si propaga anche sull'altro dispositivo,
/// facendo convergere i due DB allo stesso stato.
///
/// Eseguita a ogni avvio (v. main.dart, subito dopo runSeed): costo
/// trascurabile quando non ci sono doppioni, "si ripara da sola" se succede
/// di nuovo per qualunque motivo.
Future<void> dedupeDefaultTaxonomy(AppDatabase db) async {
  await db.transaction(() async {
    await _dedupeCategories(db);
    await _dedupeSubCategories(db);
    await _dedupeMerchantRules(db);
    await _dedupeBudgets(db);
  });
}

DateTime get _now => DateTime.now();

// --- Categorie di default ---

Future<void> _dedupeCategories(AppDatabase db) async {
  final rows = await (db.select(db.categories)
        ..where((c) => c.isDefault.equals(true) & c.isDeleted.equals(false)))
      .get();

  final groups = <String, List<Category>>{};
  for (final r in rows) {
    if (r.syncId == null) continue; // non ancora backfillata: ignorata
    groups.putIfAbsent('${r.name}|${r.type.name}', () => []).add(r);
  }

  for (final group in groups.values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.syncId!.compareTo(b.syncId!));
    final survivorId = group.first.id;

    for (final loser in group.skip(1)) {
      await (db.update(db.transactions)..where((t) => t.categoryId.equals(loser.id))).write(
        TransactionsCompanion(categoryId: Value(survivorId), updatedAt: Value(_now)),
      );
      await (db.update(db.budgets)..where((b) => b.categoryId.equals(loser.id))).write(
        BudgetsCompanion(categoryId: Value(survivorId), updatedAt: Value(_now)),
      );
      await (db.update(db.recurringTransactions)..where((r) => r.categoryId.equals(loser.id)))
          .write(RecurringTransactionsCompanion(
              categoryId: Value(survivorId), updatedAt: Value(_now)));
      await (db.update(db.merchantRules)..where((r) => r.categoryId.equals(loser.id))).write(
        MerchantRulesCompanion(categoryId: Value(survivorId), updatedAt: Value(_now)),
      );
      await (db.update(db.subCategories)..where((s) => s.categoryId.equals(loser.id))).write(
        SubCategoriesCompanion(categoryId: Value(survivorId), updatedAt: Value(_now)),
      );
      await (db.update(db.categories)..where((c) => c.id.equals(loser.id))).write(
        CategoriesCompanion(isDeleted: const Value(true), updatedAt: Value(_now)),
      );
    }
  }
}

// --- Sottocategorie (dopo il repointing delle categorie sopra) ---

Future<void> _dedupeSubCategories(AppDatabase db) async {
  final rows = await (db.select(db.subCategories)..where((s) => s.isDeleted.equals(false))).get();

  final groups = <String, List<SubCategory>>{};
  for (final r in rows) {
    if (r.syncId == null) continue;
    groups.putIfAbsent('${r.categoryId}|${r.name}', () => []).add(r);
  }

  for (final group in groups.values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.syncId!.compareTo(b.syncId!));
    final survivorId = group.first.id;

    for (final loser in group.skip(1)) {
      await (db.update(db.transactions)..where((t) => t.subCategoryId.equals(loser.id))).write(
        TransactionsCompanion(subCategoryId: Value(survivorId), updatedAt: Value(_now)),
      );
      await (db.update(db.merchantRules)..where((r) => r.subCategoryId.equals(loser.id))).write(
        MerchantRulesCompanion(subCategoryId: Value(survivorId), updatedAt: Value(_now)),
      );
      await (db.update(db.recurringTransactions)
            ..where((r) => r.subCategoryId.equals(loser.id)))
          .write(RecurringTransactionsCompanion(
              subCategoryId: Value(survivorId), updatedAt: Value(_now)));
      await (db.update(db.subCategories)..where((s) => s.id.equals(loser.id))).write(
        SubCategoriesCompanion(isDeleted: const Value(true), updatedAt: Value(_now)),
      );
    }
  }
}

// --- Regole merchant di default (nessuna FK le referenzia: solo nascondere) ---

Future<void> _dedupeMerchantRules(AppDatabase db) async {
  final rows = await (db.select(db.merchantRules)
        ..where((r) => r.isUserDefined.equals(false) & r.isDeleted.equals(false)))
      .get();

  final groups = <String, List<MerchantRule>>{};
  for (final r in rows) {
    if (r.syncId == null) continue;
    groups.putIfAbsent('${r.pattern}|${r.categoryId}|${r.subCategoryId}', () => []).add(r);
  }

  for (final group in groups.values) {
    if (group.length < 2) continue;
    group.sort((a, b) => a.syncId!.compareTo(b.syncId!));
    for (final loser in group.skip(1)) {
      await (db.update(db.merchantRules)..where((r) => r.id.equals(loser.id))).write(
        MerchantRulesCompanion(isDeleted: const Value(true), updatedAt: Value(_now)),
      );
    }
  }
}

// --- Budget (collisioni dopo il repointing categorie + doppioni indipendenti
// dal repointing, es. due totali mensili "categoria nulla" impostati separatamente
// sui due dispositivi prima della sync) ---

Future<void> _dedupeBudgets(AppDatabase db) async {
  final rows = await (db.select(db.budgets)..where((b) => b.isDeleted.equals(false))).get();

  final groups = <String, List<Budget>>{};
  for (final r in rows) {
    final key = '${r.categoryId ?? "null"}|${r.period.index}|${r.startDate.year}-${r.startDate.month}';
    groups.putIfAbsent(key, () => []).add(r);
  }

  for (final group in groups.values) {
    if (group.length < 2) continue;
    // Qui non c'è un "sopravvissuto" concettuale: sono due importi pianificati
    // in conflitto, si tiene il più recente (stessa logica last-write-wins
    // usata dal resto della sync).
    group.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final loser in group.skip(1)) {
      await (db.update(db.budgets)..where((b) => b.id.equals(loser.id))).write(
        BudgetsCompanion(isDeleted: const Value(true), updatedAt: Value(_now)),
      );
    }
  }
}
