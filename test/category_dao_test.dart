import 'package:async/async.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/budgets_table.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/database/tables/recurring_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> insertCategory(String name) {
    return db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: name,
            icon: '🏷️',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
  }

  test('senza ordine salvato, le categorie restano nell\'ordine di inserimento (per id)', () async {
    await insertCategory('Casa');
    await insertCategory('Auto');
    await insertCategory('Spesa');

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;

    expect(result.map((c) => c.name).toList(), ['Casa', 'Auto', 'Spesa']);
  });

  test('reorderCategories applica l\'ordine manuale salvato', () async {
    final casa = await insertCategory('Casa');
    final auto = await insertCategory('Auto');
    final spesa = await insertCategory('Spesa');

    await db.categoryDao.reorderCategories(TransactionKind.expense, [spesa, casa, auto]);

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;
    expect(result.map((c) => c.name).toList(), ['Spesa', 'Casa', 'Auto']);
  });

  test('una categoria creata dopo il salvataggio dell\'ordine viene accodata alla fine', () async {
    final casa = await insertCategory('Casa');
    final auto = await insertCategory('Auto');
    await db.categoryDao.reorderCategories(TransactionKind.expense, [auto, casa]);

    await insertCategory('Svago'); // non presente nell'ordine salvato

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;
    expect(result.map((c) => c.name).toList(), ['Auto', 'Casa', 'Svago']);
  });

  test('un id nell\'ordine salvato che non esiste più viene ignorato senza errori', () async {
    final casa = await insertCategory('Casa');
    const idFantasma = 9999;
    await db.categoryDao.reorderCategories(TransactionKind.expense, [idFantasma, casa]);

    final result = await db.categoryDao.watchByType(TransactionKind.expense).first;
    expect(result.map((c) => c.name).toList(), ['Casa']);
  });

  test('softDeleteCategory cancella in cascata anche le sue sottocategorie', () async {
    final casaId = await insertCategory('Casa');
    final bolletteId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(categoryId: casaId, name: 'Bollette'),
        );
    final affittoId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(categoryId: casaId, name: 'Affitto'),
        );

    await db.categoryDao.softDeleteCategory(casaId);

    final category = await (db.select(db.categories)..where((c) => c.id.equals(casaId))).getSingle();
    expect(category.isDeleted, isTrue);

    final subCategories = await (db.select(db.subCategories)
          ..where((s) => s.id.isIn([bolletteId, affittoId])))
        .get();
    expect(subCategories.every((s) => s.isDeleted), isTrue);
  });

  test('softDeleteCategory non tocca le sottocategorie di un\'altra categoria', () async {
    final casaId = await insertCategory('Casa');
    final autoId = await insertCategory('Auto');
    final carburanteId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(categoryId: autoId, name: 'Carburante'),
        );

    await db.categoryDao.softDeleteCategory(casaId);

    final carburante = await (db.select(db.subCategories)..where((s) => s.id.equals(carburanteId))).getSingle();
    expect(carburante.isDeleted, isFalse);
  });

  group('reattività del riordino su uno stream già in ascolto (senza riavviare l\'app)', () {
    // Prima del fix, questi stream erano costruiti solo sulla query di
    // categorie/sottocategorie: Drift li riemette in base alle sole tabelle
    // che quella query tocca, quindi una scrittura che cambia SOLO l'ordine
    // salvato (tabella Settings) non li faceva ripartire — l'ordine nuovo si
    // vedeva solo dopo un riavvio dell'app (bug segnalato dall'utente).

    test('watchByType riemette con il nuovo ordine appena si chiama reorderCategories', () async {
      final casa = await insertCategory('Casa');
      final auto = await insertCategory('Auto');
      final queue = StreamQueue(db.categoryDao.watchByType(TransactionKind.expense));

      final first = await queue.next;
      expect(first.map((c) => c.name).toList(), ['Casa', 'Auto']);

      await db.categoryDao.reorderCategories(TransactionKind.expense, [auto, casa]);

      final second = await queue.next;
      expect(second.map((c) => c.name).toList(), ['Auto', 'Casa']);

      await queue.cancel();
    });

    test('watchSubCategories riemette con il nuovo ordine appena si chiama reorderSubCategories', () async {
      final casaId = await insertCategory('Casa');
      final bollette = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Bollette'),
          );
      final affitto = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Affitto'),
          );
      final queue = StreamQueue(db.categoryDao.watchSubCategories(casaId));

      final first = await queue.next;
      expect(first.map((s) => s.name).toList(), ['Bollette', 'Affitto']);

      await db.categoryDao.reorderSubCategories(casaId, [affitto, bollette]);

      final second = await queue.next;
      expect(second.map((s) => s.name).toList(), ['Affitto', 'Bollette']);

      await queue.cancel();
    });

    test('watchSubCategoriesForType riemette con il nuovo ordine (categorie e sottocategorie) senza ricreare la subscription', () async {
      final casaId = await insertCategory('Casa');
      final autoId = await insertCategory('Auto');
      final bollette = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Bollette'),
          );
      final affitto = await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: casaId, name: 'Affitto'),
          );
      final queue = StreamQueue(db.categoryDao.watchSubCategoriesForType(TransactionKind.expense));

      final first = await queue.next;
      expect(first.map((i) => '${i.category.name}/${i.subCategory.name}').toList(),
          ['Casa/Bollette', 'Casa/Affitto']);

      // Riordina prima le categorie (Auto prima di Casa): tocca solo
      // Settings, nessuna riga di Categories/SubCategories.
      await db.categoryDao.reorderCategories(TransactionKind.expense, [autoId, casaId]);
      final second = await queue.next;
      expect(second.map((i) => '${i.category.name}/${i.subCategory.name}').toList(),
          ['Casa/Bollette', 'Casa/Affitto'],
          reason: 'categoria riordinata, sottocategorie di Casa ancora nell\'ordine originale');

      // Poi le sottocategorie di Casa (Affitto prima di Bollette): stessa
      // storia, solo Settings.
      await db.categoryDao.reorderSubCategories(casaId, [affitto, bollette]);
      final third = await queue.next;
      expect(third.map((i) => '${i.category.name}/${i.subCategory.name}').toList(),
          ['Casa/Affitto', 'Casa/Bollette']);

      await queue.cancel();
    });
  });

  group('unione categorie/sottocategorie (risolve doppioni senza script sul DB)', () {
    Future<int> insertSubCategory(int categoryId, String name) {
      return db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(categoryId: categoryId, name: name),
          );
    }

    Future<int> insertTransaction({
      required int categoryId,
      int? subCategoryId,
    }) {
      return db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              date: DateTime(2026, 1, 1),
              amount: 10,
              type: TransactionKind.expense,
              categoryId: categoryId,
              subCategoryId: Value(subCategoryId),
            ),
          );
    }

    Future<int> insertMerchantRule({
      required int categoryId,
      int? subCategoryId,
    }) {
      return db.into(db.merchantRules).insert(
            MerchantRulesCompanion.insert(
              pattern: 'ESSELUNGA.*',
              categoryId: categoryId,
              subCategoryId: Value(subCategoryId),
            ),
          );
    }

    Future<int> insertBudget(int categoryId) {
      return db.into(db.budgets).insert(
            BudgetsCompanion.insert(
              period: BudgetPeriod.monthly,
              amount: 100,
              startDate: DateTime(2026, 1, 1),
              categoryId: Value(categoryId),
            ),
          );
    }

    Future<int> insertRecurring({
      required int categoryId,
      int? subCategoryId,
    }) {
      return db.into(db.recurringTransactions).insert(
            RecurringTransactionsCompanion.insert(
              description: 'Netflix',
              amount: 12.99,
              type: TransactionKind.expense,
              categoryId: categoryId,
              subCategoryId: Value(subCategoryId),
              frequency: RecurringFrequency.monthly,
              nextOccurrence: DateTime(2026, 2, 1),
            ),
          );
    }

    test('mergeCategoryInto sposta transazioni/regole/budget/ricorrenze e cancella la sorgente', () async {
      final casa = await insertCategory('Casa');
      final casaBis = await insertCategory('Casa (doppione)');
      final txId = await insertTransaction(categoryId: casaBis);
      final ruleId = await insertMerchantRule(categoryId: casaBis);
      final budgetId = await insertBudget(casaBis);
      final recurringId = await insertRecurring(categoryId: casaBis);

      await db.categoryDao.mergeCategoryInto(sourceId: casaBis, targetId: casa);

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId))).getSingle();
      expect(tx.categoryId, casa);
      final rule = await (db.select(db.merchantRules)..where((r) => r.id.equals(ruleId))).getSingle();
      expect(rule.categoryId, casa);
      final budget = await (db.select(db.budgets)..where((b) => b.id.equals(budgetId))).getSingle();
      expect(budget.categoryId, casa);
      final recurring =
          await (db.select(db.recurringTransactions)..where((r) => r.id.equals(recurringId))).getSingle();
      expect(recurring.categoryId, casa);

      final source = await (db.select(db.categories)..where((c) => c.id.equals(casaBis))).getSingle();
      expect(source.isDeleted, isTrue);
    });

    test('mergeCategoryInto rifiuta se una sottocategoria attiva ha ancora transazioni collegate', () async {
      final casa = await insertCategory('Casa');
      final casaBis = await insertCategory('Casa (doppione)');
      final bollette = await insertSubCategory(casaBis, 'Bollette');
      await insertTransaction(categoryId: casaBis, subCategoryId: bollette);

      expect(
        () => db.categoryDao.mergeCategoryInto(sourceId: casaBis, targetId: casa),
        throwsA(isA<StateError>()),
      );
    });

    test('mergeCategoryInto procede se le sottocategorie della sorgente sono vuote (vengono cancellate a cascata)', () async {
      final casa = await insertCategory('Casa');
      final casaBis = await insertCategory('Casa (doppione)');
      final vuota = await insertSubCategory(casaBis, 'Sottocategoria vuota');

      await db.categoryDao.mergeCategoryInto(sourceId: casaBis, targetId: casa);

      final subCategory = await (db.select(db.subCategories)..where((s) => s.id.equals(vuota))).getSingle();
      expect(subCategory.isDeleted, isTrue);
    });

    test('mergeSubCategoryInto sposta transazioni/regole/ricorrenze anche verso una categoria padre diversa', () async {
      final salute = await insertCategory('Salute');
      final saluteBis = await insertCategory('Salute (doppione)');
      final farmacia = await insertSubCategory(salute, 'Farmacia');
      final medicoFarmaci = await insertSubCategory(saluteBis, 'Medico / Farmaci');
      final txId = await insertTransaction(categoryId: saluteBis, subCategoryId: medicoFarmaci);
      final ruleId = await insertMerchantRule(categoryId: saluteBis, subCategoryId: medicoFarmaci);
      final recurringId = await insertRecurring(categoryId: saluteBis, subCategoryId: medicoFarmaci);

      await db.categoryDao.mergeSubCategoryInto(sourceId: medicoFarmaci, targetId: farmacia);

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId))).getSingle();
      expect(tx.categoryId, salute);
      expect(tx.subCategoryId, farmacia);
      final rule = await (db.select(db.merchantRules)..where((r) => r.id.equals(ruleId))).getSingle();
      expect(rule.categoryId, salute);
      expect(rule.subCategoryId, farmacia);
      final recurring =
          await (db.select(db.recurringTransactions)..where((r) => r.id.equals(recurringId))).getSingle();
      expect(recurring.categoryId, salute);
      expect(recurring.subCategoryId, farmacia);

      final source = await (db.select(db.subCategories)..where((s) => s.id.equals(medicoFarmaci))).getSingle();
      expect(source.isDeleted, isTrue);
    });

    test('categoryMergeImpact/subCategoryMergeImpact contano solo le righe non cancellate', () async {
      final casa = await insertCategory('Casa');
      final casaBis = await insertCategory('Casa (doppione)');
      await insertTransaction(categoryId: casaBis);
      final txCancellataId = await insertTransaction(categoryId: casaBis);
      await db.transactionDao.softDelete(txCancellataId);
      await insertMerchantRule(categoryId: casaBis);
      await insertBudget(casaBis);

      final impact = await db.categoryDao.categoryMergeImpact(casaBis);
      expect(impact.transactions, 1);
      expect(impact.merchantRules, 1);
      expect(impact.budgets, 1);
      expect(impact.recurringTransactions, 0);
      expect(impact.total, 3);

      final bollette = await insertSubCategory(casa, 'Bollette');
      await insertTransaction(categoryId: casa, subCategoryId: bollette);

      final subImpact = await db.categoryDao.subCategoryMergeImpact(bollette);
      expect(subImpact.transactions, 1);
      expect(subImpact.budgets, 0);
    });

    test('categoryHasBlockingSubCategories distingue sottocategorie vuote da quelle con dati', () async {
      final casa = await insertCategory('Casa');
      expect(await db.categoryDao.categoryHasBlockingSubCategories(casa), isFalse);

      final vuota = await insertSubCategory(casa, 'Vuota');
      expect(await db.categoryDao.categoryHasBlockingSubCategories(casa), isFalse);

      await insertTransaction(categoryId: casa, subCategoryId: vuota);
      expect(await db.categoryDao.categoryHasBlockingSubCategories(casa), isTrue);
    });

    test('unire una categoria/sottocategoria con se stessa lancia un errore', () async {
      final casa = await insertCategory('Casa');
      final bollette = await insertSubCategory(casa, 'Bollette');

      expect(
        () => db.categoryDao.mergeCategoryInto(sourceId: casa, targetId: casa),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => db.categoryDao.mergeSubCategoryInto(sourceId: bollette, targetId: bollette),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
