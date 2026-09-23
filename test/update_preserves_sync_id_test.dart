import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/repositories_impl/category_repository_impl.dart';
import 'package:finance_app/data/repositories_impl/merchant_rule_repository_impl.dart';
import 'package:finance_app/data/repositories_impl/recurring_repository_impl.dart';
import 'package:finance_app/data/repositories_impl/transaction_repository_impl.dart';
import 'package:finance_app/domain/entities/category_entity.dart';
import 'package:finance_app/domain/entities/merchant_rule_entity.dart';
import 'package:finance_app/domain/entities/recurring_entity.dart';
import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modificare un elemento dall'app (stesso percorso dei form: repository →
/// DAO) non deve mai perdere il suo `syncId`: è l'identità della riga tra
/// dispositivi. Se si azzera, la riga smette di sincronizzarsi e al riavvio
/// ne riceve uno nuovo (v. `_backfillSyncIds`), diventando una riga
/// "diversa" sul server — cioè un doppione su tutti gli altri dispositivi.
void main() {
  late AppDatabase db;
  late CategoryRepositoryImpl categories;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categories = CategoryRepositoryImpl(db.categoryDao);
  });

  tearDown(() => db.close());

  Future<int> addCategory() => categories.addCategory(const CategoryEntity(
        name: 'Casa',
        icon: '🏠',
        type: TransactionType.expense,
        color: 0xFF8D6E63,
      ));

  test('modifica categoria', () async {
    final id = await addCategory();
    final before = (await db.categoryDao.getCategoryById(id))!;
    expect(before.syncId, isNotNull);

    await categories.updateCategory(CategoryEntity(
      id: id,
      name: 'Casa e bollette',
      icon: '🏠',
      type: TransactionType.expense,
      color: 0xFF8D6E63,
    ));

    final after = (await db.categoryDao.getCategoryById(id))!;
    expect(after.name, 'Casa e bollette');
    expect(after.syncId, before.syncId);
  });

  test('modifica sottocategoria', () async {
    final categoryId = await addCategory();
    final id = await categories.addSubCategory(
        SubCategoryEntity(categoryId: categoryId, name: 'Bollette'));
    final before = (await db.categoryDao.getSubCategoryById(id))!;
    expect(before.syncId, isNotNull);

    await categories.updateSubCategory(
        SubCategoryEntity(id: id, categoryId: categoryId, name: 'Utenze'));

    final after = (await db.categoryDao.getSubCategoryById(id))!;
    expect(after.name, 'Utenze');
    expect(after.syncId, before.syncId);
  });

  test('modifica transazione', () async {
    final categoryId = await addCategory();
    final repo = TransactionRepositoryImpl(db.transactionDao);
    final entity = TransactionEntity(
      date: DateTime(2026, 9, 1),
      amount: 10,
      type: TransactionType.expense,
      categoryId: categoryId,
      note: 'Spesa',
    );
    final id = await repo.add(entity);
    final before = (await db.transactionDao.getById(id))!;
    expect(before.syncId, isNotNull);

    await repo.update(entity.copyWith(id: id, amount: 12));

    final after = (await db.transactionDao.getById(id))!;
    expect(after.amount, 12);
    expect(after.syncId, before.syncId);
    expect(after.createdAt, before.createdAt);
  });

  test('modifica regola di classificazione', () async {
    final categoryId = await addCategory();
    final repo = MerchantRuleRepositoryImpl(db.merchantRuleDao);
    final id = await repo.addRule(MerchantRuleEntity(pattern: 'ESSEL', categoryId: categoryId));
    Future<MerchantRule> read() =>
        (db.select(db.merchantRules)..where((r) => r.id.equals(id))).getSingle();
    final before = await read();
    expect(before.syncId, isNotNull);

    await repo.updateRule(MerchantRuleEntity(id: id, pattern: 'ESSELUNGA', categoryId: categoryId));

    final after = await read();
    expect(after.pattern, 'ESSELUNGA');
    expect(after.syncId, before.syncId);
  });

  test('modifica ricorrenza', () async {
    final categoryId = await addCategory();
    final repo = RecurringRepositoryImpl(db.recurringDao);
    final entity = RecurringEntity(
      description: 'Netflix',
      amount: 12.99,
      type: TransactionType.expense,
      categoryId: categoryId,
      frequency: RecurringFrequencyType.monthly,
      nextOccurrence: DateTime(2026, 10, 1),
    );
    final id = await repo.add(entity);
    final before = (await db.recurringDao.getById(id))!;
    expect(before.syncId, isNotNull);

    await repo.update(entity.copyWith(id: id, amount: 13.99));

    final after = (await db.recurringDao.getById(id))!;
    expect(after.amount, 13.99);
    expect(after.syncId, before.syncId);
  });

  // M53: se l'elemento viene eliminato mentre il suo form di modifica è
  // aperto (es. l'eliminazione arriva via sync da un altro dispositivo),
  // premere Salva non deve riportarlo attivo — altrimenti, col suo
  // updatedAt nuovo, vincerebbe alla sync e ricomparirebbe ovunque.
  group('salvare un form aperto su un elemento eliminato nel frattempo', () {
    test('categoria', () async {
      final id = await addCategory();
      await (db.update(db.categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(isDeleted: Value(true)));

      await categories.updateCategory(CategoryEntity(
        id: id,
        name: 'Casa e bollette',
        icon: '🏠',
        type: TransactionType.expense,
        color: 0xFF8D6E63,
      ));

      expect((await db.categoryDao.getCategoryById(id))!.isDeleted, isTrue);
    });

    test('sottocategoria', () async {
      final categoryId = await addCategory();
      final id = await categories.addSubCategory(
          SubCategoryEntity(categoryId: categoryId, name: 'Bollette'));
      await db.categoryDao.softDeleteSubCategory(id);

      await categories.updateSubCategory(
          SubCategoryEntity(id: id, categoryId: categoryId, name: 'Utenze'));

      expect((await db.categoryDao.getSubCategoryById(id))!.isDeleted, isTrue);
    });

    test('transazione (e createdAt resta quello originale)', () async {
      final categoryId = await addCategory();
      final repo = TransactionRepositoryImpl(db.transactionDao);
      final entity = TransactionEntity(
        date: DateTime(2026, 9, 1),
        amount: 10,
        type: TransactionType.expense,
        categoryId: categoryId,
      );
      final id = await repo.add(entity);
      final createdAt = DateTime(2020, 1, 1);
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
          TransactionsCompanion(createdAt: Value(createdAt), isDeleted: const Value(true)));

      await repo.update(entity.copyWith(id: id, amount: 12));

      final after = (await db.transactionDao.getById(id))!;
      expect(after.isDeleted, isTrue);
      expect(after.amount, 12);
      expect(after.createdAt, createdAt);
    });

    test('regola di classificazione', () async {
      final categoryId = await addCategory();
      final repo = MerchantRuleRepositoryImpl(db.merchantRuleDao);
      final id = await repo.addRule(MerchantRuleEntity(pattern: 'ESSEL', categoryId: categoryId));
      await db.merchantRuleDao.softDelete(id);

      await repo.updateRule(
          MerchantRuleEntity(id: id, pattern: 'ESSELUNGA', categoryId: categoryId));

      final after =
          await (db.select(db.merchantRules)..where((r) => r.id.equals(id))).getSingle();
      expect(after.isDeleted, isTrue);
    });

    test('ricorrenza', () async {
      final categoryId = await addCategory();
      final repo = RecurringRepositoryImpl(db.recurringDao);
      final entity = RecurringEntity(
        description: 'Netflix',
        amount: 12.99,
        type: TransactionType.expense,
        categoryId: categoryId,
        frequency: RecurringFrequencyType.monthly,
        nextOccurrence: DateTime(2026, 10, 1),
      );
      final id = await repo.add(entity);
      await db.recurringDao.softDelete(id);

      await repo.update(entity.copyWith(id: id, amount: 13.99));

      expect((await db.recurringDao.getById(id))!.isDeleted, isTrue);
    });
  });
}
