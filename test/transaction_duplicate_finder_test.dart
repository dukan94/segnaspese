import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/services/transaction_duplicate_finder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int categoryId;
  late int subCategoryId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Fuori Casa',
            icon: '🍔',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
    subCategoryId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(
            categoryId: categoryId,
            name: 'Ristorante / Uscita',
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> insertTransaction({
    required String syncId,
    DateTime? date,
    double amount = 25.0,
    String? note = 'Cena',
    bool isDeleted = false,
  }) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            date: date ?? DateTime(2026, 7, 24),
            amount: amount,
            type: TransactionKind.expense,
            categoryId: categoryId,
            subCategoryId: Value(subCategoryId),
            note: Value(note),
            isDeleted: Value(isDeleted),
            syncId: Value(syncId),
          ),
        );
  }

  Future<Transaction?> find({
    required String excludeSyncId,
    DateTime? date,
    double amount = 25.0,
    String? note = 'Cena',
  }) {
    return findContentDuplicateTransaction(
      db,
      date: date ?? DateTime(2026, 7, 24),
      amount: amount,
      type: TransactionKind.expense,
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      isRefund: false,
      note: note,
      excludeSyncId: excludeSyncId,
    );
  }

  test('trova una transazione locale identica con syncId diverso', () async {
    await insertTransaction(syncId: 'local-1');

    final found = await find(excludeSyncId: 'remote-2');

    expect(found, isNotNull);
    expect(found!.syncId, 'local-1');
  });

  test('non trova nulla se il syncId coincide (è la stessa riga)', () async {
    await insertTransaction(syncId: 'same-id');

    final found = await find(excludeSyncId: 'same-id');

    expect(found, isNull);
  });

  test('non trova nulla se importo diverso', () async {
    await insertTransaction(syncId: 'local-1', amount: 25.0);

    final found = await find(excludeSyncId: 'remote-2', amount: 30.0);

    expect(found, isNull);
  });

  test('non trova nulla se la nota è diversa', () async {
    await insertTransaction(syncId: 'local-1', note: 'Cena');

    final found = await find(excludeSyncId: 'remote-2', note: 'Pranzo');

    expect(found, isNull);
  });

  test('non trova nulla se la transazione locale è già cancellata', () async {
    await insertTransaction(syncId: 'local-1', isDeleted: true);

    final found = await find(excludeSyncId: 'remote-2');

    expect(found, isNull);
  });
}
