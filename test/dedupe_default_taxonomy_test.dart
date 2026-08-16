import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/budgets_table.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/seed/dedupe_default_taxonomy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> insertCategory(
    String name, {
    bool isDefault = true,
    String? syncId,
    TransactionKind type = TransactionKind.expense,
  }) {
    return db.into(db.categories).insert(CategoriesCompanion.insert(
          name: name,
          icon: '📦',
          type: type,
          color: 0xFF000000,
          isDefault: Value(isDefault),
          syncId: Value(syncId),
        ));
  }

  Future<int> insertSubCategory(int categoryId, String name, {String? syncId}) {
    return db.into(db.subCategories).insert(SubCategoriesCompanion.insert(
          categoryId: categoryId,
          name: name,
          syncId: Value(syncId),
        ));
  }

  Future<int> insertMerchantRule(
    String pattern,
    int categoryId, {
    bool isUserDefined = false,
    String? syncId,
  }) {
    return db.into(db.merchantRules).insert(MerchantRulesCompanion.insert(
          pattern: pattern,
          categoryId: categoryId,
          isUserDefined: Value(isUserDefined),
          syncId: Value(syncId),
        ));
  }

  Future<int> insertTransaction(int categoryId, {int? subCategoryId}) {
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          date: DateTime(2026, 8, 1),
          amount: 10,
          type: TransactionKind.expense,
          categoryId: categoryId,
          subCategoryId: Value(subCategoryId),
        ));
  }

  Future<int> insertBudget(
    int? categoryId, {
    required DateTime updatedAt,
    double amount = 100,
  }) {
    return db.into(db.budgets).insert(BudgetsCompanion.insert(
          categoryId: Value(categoryId),
          period: BudgetPeriod.monthly,
          amount: amount,
          startDate: DateTime(2026, 8, 1),
          updatedAt: Value(updatedAt),
        ));
  }

  group('dedupe categorie di default', () {
    test(
        'tiene la categoria col syncId più basso, ripunta transazioni/budget '
        'e nasconde l\'altra', () async {
      final survivorId =
          await insertCategory('Casa', syncId: 'aaa-sopravvive');
      final loserId = await insertCategory('Casa', syncId: 'zzz-perde');
      final txId = await insertTransaction(loserId);
      final budgetId = await insertBudget(loserId, updatedAt: DateTime(2026, 1, 1));

      await dedupeDefaultTaxonomy(db);

      final survivor =
          await (db.select(db.categories)..where((c) => c.id.equals(survivorId)))
              .getSingle();
      final loser =
          await (db.select(db.categories)..where((c) => c.id.equals(loserId)))
              .getSingle();
      final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
          .getSingle();
      final budget = await (db.select(db.budgets)..where((b) => b.id.equals(budgetId)))
          .getSingle();

      expect(survivor.isDeleted, isFalse);
      expect(loser.isDeleted, isTrue);
      expect(tx.categoryId, survivorId);
      expect(budget.categoryId, survivorId);
    });

    test('categorie non di default con lo stesso nome non vengono mai toccate',
        () async {
      await insertCategory('Personalizzata', isDefault: false, syncId: 'a');
      await insertCategory('Personalizzata', isDefault: false, syncId: 'b');

      await dedupeDefaultTaxonomy(db);

      final all = await db.select(db.categories).get();
      expect(all.every((c) => !c.isDeleted), isTrue);
    });

    test('categorie senza syncId (non ancora backfillate) vengono ignorate',
        () async {
      await insertCategory('Casa', syncId: null);
      await insertCategory('Casa', syncId: null);

      await dedupeDefaultTaxonomy(db);

      final all = await db.select(db.categories).get();
      expect(all.every((c) => !c.isDeleted), isTrue);
    });
  });

  group('dedupe sottocategorie', () {
    test(
        'tiene la sottocategoria col syncId più basso, ripunta le '
        'transazioni e nasconde l\'altra', () async {
      final categoryId = await insertCategory('Casa', syncId: 'cat-1');
      final survivorId =
          await insertSubCategory(categoryId, 'Spesa', syncId: 'aaa');
      final loserId =
          await insertSubCategory(categoryId, 'Spesa', syncId: 'zzz');
      final txId = await insertTransaction(categoryId, subCategoryId: loserId);

      await dedupeDefaultTaxonomy(db);

      final loser = await (db.select(db.subCategories)
            ..where((s) => s.id.equals(loserId)))
          .getSingle();
      final tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
          .getSingle();

      expect(loser.isDeleted, isTrue);
      expect(tx.subCategoryId, survivorId);
    });
  });

  group('dedupe regole merchant', () {
    test(
        'due regole non-utente con stesso pattern/categoria: quella con '
        'syncId più alto viene nascosta', () async {
      final categoryId = await insertCategory('Casa', syncId: 'cat-1');
      final survivorId = await insertMerchantRule('ESSEL.*', categoryId,
          syncId: 'aaa-sopravvive');
      final loserId =
          await insertMerchantRule('ESSEL.*', categoryId, syncId: 'zzz-perde');

      await dedupeDefaultTaxonomy(db);

      final survivor = await (db.select(db.merchantRules)
            ..where((r) => r.id.equals(survivorId)))
          .getSingle();
      final loser = await (db.select(db.merchantRules)
            ..where((r) => r.id.equals(loserId)))
          .getSingle();

      expect(survivor.isDeleted, isFalse);
      expect(loser.isDeleted, isTrue);
    });

    test('le regole create dall\'utente (isUserDefined) non vengono mai toccate',
        () async {
      final categoryId = await insertCategory('Casa', syncId: 'cat-1');
      await insertMerchantRule('ESSEL.*', categoryId,
          isUserDefined: true, syncId: 'a');
      await insertMerchantRule('ESSEL.*', categoryId,
          isUserDefined: true, syncId: 'b');

      await dedupeDefaultTaxonomy(db);

      final all = await db.select(db.merchantRules).get();
      expect(all.every((r) => !r.isDeleted), isTrue);
    });
  });

  group('dedupe budget', () {
    test(
        'due budget in conflitto sulla stessa categoria/periodo/mese: '
        'tiene il più recente (last-write-wins)', () async {
      final categoryId = await insertCategory('Casa', syncId: 'cat-1');
      final olderId = await insertBudget(categoryId, updatedAt: DateTime(2026, 1, 1));
      final newerId = await insertBudget(categoryId, updatedAt: DateTime(2026, 6, 1));

      await dedupeDefaultTaxonomy(db);

      final older =
          await (db.select(db.budgets)..where((b) => b.id.equals(olderId)))
              .getSingle();
      final newer =
          await (db.select(db.budgets)..where((b) => b.id.equals(newerId)))
              .getSingle();

      expect(older.isDeleted, isTrue);
      expect(newer.isDeleted, isFalse);
    });
  });

  group('nessun doppione', () {
    test('non fa nulla se non ci sono duplicati', () async {
      await insertCategory('Casa', syncId: 'a');
      await insertCategory('Auto', syncId: 'b');

      await dedupeDefaultTaxonomy(db);

      final all = await db.select(db.categories).get();
      expect(all.every((c) => !c.isDeleted), isTrue);
    });
  });
}
