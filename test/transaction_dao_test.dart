import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int categoriaCasa;
  late int categoriaAuto;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaCasa = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Casa', icon: '🏠', type: TransactionKind.expense, color: 0xFF000000),
        );
    categoriaAuto = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Auto', icon: '🚗', type: TransactionKind.expense, color: 0xFF000000),
        );
  });

  tearDown(() => db.close());

  Future<int> insertTransazione({
    required int categoryId,
    required double amount,
    required DateTime date,
    String? note,
    bool isDeleted = false,
  }) {
    return db.transactionDao.insertTransaction(
      TransactionsCompanion.insert(
        date: date,
        amount: amount,
        type: TransactionKind.expense,
        categoryId: categoryId,
        note: Value(note),
        isDeleted: Value(isDeleted),
      ),
    );
  }

  test('search per categoria: restituisce solo le transazioni di quella categoria', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 50, date: DateTime(2025, 6, 1));
    await insertTransazione(categoryId: categoriaAuto, amount: 50, date: DateTime(2025, 6, 1));

    final result = await db.transactionDao.search(categoryId: categoriaCasa);

    expect(result, hasLength(1));
    expect(result.single.categoryId, categoriaCasa);
  });

  test('search per importo esatto', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 19.99, date: DateTime(2025, 6, 1));
    await insertTransazione(categoryId: categoriaCasa, amount: 25, date: DateTime(2025, 6, 1));

    final result = await db.transactionDao.search(amount: 19.99);

    expect(result, hasLength(1));
    expect(result.single.amount, 19.99);
  });

  test('search per data: include l\'intera giornata indipendentemente dall\'orario', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 10, date: DateTime(2025, 6, 10, 23, 59));
    await insertTransazione(categoryId: categoriaCasa, amount: 20, date: DateTime(2025, 6, 11, 0, 1));

    final result = await db.transactionDao.search(date: DateTime(2025, 6, 10));

    expect(result, hasLength(1));
    expect(result.single.amount, 10);
  });

  test('search per nota: match parziale case-sensitive su substring', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 10, date: DateTime(2025, 6, 1), note: 'Bolletta luce');
    await insertTransazione(categoryId: categoriaCasa, amount: 20, date: DateTime(2025, 6, 1), note: 'Spesa supermercato');

    final result = await db.transactionDao.search(note: 'luce');

    expect(result, hasLength(1));
    expect(result.single.note, 'Bolletta luce');
  });

  test('search combina i filtri in AND: categoria giusta ma importo sbagliato non trova nulla', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 50, date: DateTime(2025, 6, 1));

    final result = await db.transactionDao.search(categoryId: categoriaCasa, amount: 999);

    expect(result, isEmpty);
  });

  test('search ignora sempre le transazioni cancellate, anche se combaciano con i filtri', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 50, date: DateTime(2025, 6, 1), isDeleted: true);

    final result = await db.transactionDao.search(categoryId: categoriaCasa);

    expect(result, isEmpty);
  });

  test('search senza filtri restituisce tutte le transazioni non cancellate', () async {
    await insertTransazione(categoryId: categoriaCasa, amount: 50, date: DateTime(2025, 6, 1));
    await insertTransazione(categoryId: categoriaAuto, amount: 30, date: DateTime(2025, 6, 2));

    final result = await db.transactionDao.search();

    expect(result, hasLength(2));
  });
}
