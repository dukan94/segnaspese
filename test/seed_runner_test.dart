import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/seed/seed_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<String?> seedVersionValue() async {
    final row = await (db.select(db.settings)
          ..where((s) => s.key.equals('seed_version')))
        .getSingleOrNull();
    return row?.value;
  }

  group('primo avvio (DB vuoto)', () {
    test('popola categorie/sottocategorie/regole e scrive la versione seed',
        () async {
      await runSeed(db);

      final categories = await db.select(db.categories).get();
      final subCategories = await db.select(db.subCategories).get();
      final rules = await db.select(db.merchantRules).get();

      expect(categories, isNotEmpty);
      expect(subCategories, isNotEmpty);
      expect(rules, isNotEmpty);
      expect(seedVersionValue(), completion(kSeedVersion.toString()));
    });
  });

  group('versione già allineata', () {
    test('non fa nulla: dati esistenti (anche non-default) restano invariati',
        () async {
      await runSeed(db);
      final categoriesAfterFirstSeed = await db.select(db.categories).get();

      // Aggiunge una categoria "a mano" (simula una creata dall'utente),
      // scenario che runSeed non deve mai toccare quando la versione è già
      // allineata: non è un reset incondizionato, solo un allineamento.
      await db.into(db.categories).insert(CategoriesCompanion.insert(
            name: 'Categoria utente',
            icon: '🧾',
            type: TransactionKind.expense,
            color: 0xFF123456,
          ));

      await runSeed(db);

      final categoriesAfterSecondSeed = await db.select(db.categories).get();
      expect(categoriesAfterSecondSeed.length,
          categoriesAfterFirstSeed.length + 1);
      expect(
        categoriesAfterSecondSeed.map((c) => c.name),
        contains('Categoria utente'),
      );
    });
  });

  group('versione seed cambiata, con dati già presenti (reset pulito)', () {
    test(
        'svuota transazioni/budget/ricorrenze/categorie e ripopola con i '
        'default, aggiornando la versione seed', () async {
      // Simula un DB creato da una versione precedente della tassonomia:
      // una categoria "vecchia" con una transazione collegata, e la chiave
      // seed_version deliberatamente non allineata a kSeedVersion.
      final oldCategoryId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'Tassonomia vecchia',
              icon: '📦',
              type: TransactionKind.expense,
              color: 0xFF000000,
            ),
          );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              date: DateTime(2026, 1, 1),
              amount: 10,
              type: TransactionKind.expense,
              categoryId: oldCategoryId,
            ),
          );
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'seed_version',
              value: '${kSeedVersion - 1}',
              updatedAt: Value(DateTime.now()),
            ),
          );
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'category_order_expense',
              value: '$oldCategoryId',
              updatedAt: Value(DateTime.now()),
            ),
          );

      await runSeed(db);

      final categories = await db.select(db.categories).get();
      final transactions = await db.select(db.transactions).get();
      final categoryOrderRow = await (db.select(db.settings)
            ..where((s) => s.key.equals('category_order_expense')))
          .getSingleOrNull();

      expect(categories.map((c) => c.name), isNot(contains('Tassonomia vecchia')));
      expect(categories, isNotEmpty); // ripopolata con i default
      expect(transactions, isEmpty); // svuotata dal reset
      expect(categoryOrderRow, null); // ordinamento manuale (id vecchi) rimosso
      expect(seedVersionValue(), completion(kSeedVersion.toString()));
    });
  });

  group('versione seed cambiata, ma nessuna categoria presente', () {
    test('salta il reset (niente da svuotare) e popola direttamente',
        () async {
      // Chiave seed_version assente del tutto (es. DB creato prima che
      // fosse tracciata) ma nessuna categoria: hasData è false, non deve
      // lanciarsi in un reset che non avrebbe nulla da cancellare.
      final categoriesBefore = await db.select(db.categories).get();
      expect(categoriesBefore, isEmpty);

      await runSeed(db);

      final categories = await db.select(db.categories).get();
      expect(categories, isNotEmpty);
      expect(seedVersionValue(), completion(kSeedVersion.toString()));
    });
  });
}
