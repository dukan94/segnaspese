import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'default_categories_seed.dart';
import 'default_merchant_rules_seed.dart';
import 'default_subcategories_seed.dart';

/// Versione della tassonomia di default (categorie / sottocategorie / regole).
///
/// Incrementare questo numero ogni volta che cambiano i dati seed: al primo
/// avvio successivo il database viene riportato ("reset pulito") alla nuova
/// tassonomia. Evita di dover individuare ed eliminare a mano il file SQLite
/// in AppData.
const int kSeedVersion = 3;

const String _seedVersionKey = 'seed_version';

/// Applica i dati di default al database, se necessario.
///
/// - Primo avvio assoluto: popola categorie, sottocategorie e regole.
/// - Versione seed cambiata: esegue un reset pulito (svuota le tabelle
///   dipendenti dalla tassonomia — comprese transazioni/budget di test, che
///   punterebbero a id non più validi — e i relativi ordinamenti manuali),
///   poi ripopola con i default correnti.
/// - Versione già allineata: non fa nulla.
Future<void> runSeed(AppDatabase db) async {
  final row = await (db.select(db.settings)
        ..where((s) => s.key.equals(_seedVersionKey)))
      .getSingleOrNull();
  final current = int.tryParse(row?.value ?? '');

  if (current == kSeedVersion) return; // già allineato

  // Se esistono già delle categorie ma la versione seed non è quella corrente
  // (inclusi i DB creati prima che questa versione fosse tracciata, dove la
  // chiave è assente), la tassonomia va sostituita: reset pulito.
  final hasData = (await (db.select(db.categories)..limit(1)).get()).isNotEmpty;

  if (hasData) {
    // Reset pulito: la tassonomia è cambiata rispetto a quella già presente.
    await db.transaction(() async {
      await db.delete(db.budgets).go();
      await db.delete(db.transactions).go();
      await db.delete(db.recurringTransactions).go();
      await db.delete(db.merchantRules).go();
      await db.delete(db.merchants).go();
      await db.delete(db.subCategories).go();
      await db.delete(db.categories).go();
      // Ordinamenti manuali salvati (riferivano i vecchi id).
      await (db.delete(db.settings)..where((s) => s.key.like('category_order_%')))
          .go();
      await (db.delete(db.settings)
            ..where((s) => s.key.like('subcategory_order_%')))
          .go();
    });
  }

  await seedDefaultCategories(db);
  await seedDefaultSubCategories(db);
  await seedDefaultMerchantRules(db);

  await db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: _seedVersionKey,
          value: '$kSeedVersion',
        ),
      );
}
