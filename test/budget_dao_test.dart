import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int categoryId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Spesa',
            icon: '🛒',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
  });

  tearDown(() => db.close());

  test('upsertMonthlyBudget: prima chiamata inserisce, la seconda sullo stesso mese aggiorna la stessa riga', () async {
    final month = DateTime(2025, 6, 1);

    await db.budgetDao.upsertMonthlyBudget(month: month, amount: 1000);
    await db.budgetDao.upsertMonthlyBudget(month: month, amount: 1200);

    final rows = await db.budgetDao.watchByMonth(month).first;
    expect(rows, hasLength(1));
    expect(rows.single.amount, 1200);
  });

  test('budget totale (categoryId nullo) e budget di categoria nello stesso mese restano righe separate', () async {
    final month = DateTime(2025, 6, 1);

    await db.budgetDao.upsertMonthlyBudget(month: month, amount: 1000);
    await db.budgetDao.upsertMonthlyBudget(month: month, categoryId: categoryId, amount: 200);

    final rows = await db.budgetDao.watchByMonth(month).first;
    expect(rows, hasLength(2));
    expect(rows.where((b) => b.categoryId == null).single.amount, 1000);
    expect(rows.where((b) => b.categoryId == categoryId).single.amount, 200);
  });

  test('mesi diversi con lo stesso categoryId non si sovrascrivono', () async {
    await db.budgetDao.upsertMonthlyBudget(month: DateTime(2025, 1, 1), categoryId: categoryId, amount: 100);
    await db.budgetDao.upsertMonthlyBudget(month: DateTime(2025, 2, 1), categoryId: categoryId, amount: 300);

    final gennaio = await db.budgetDao.watchByMonth(DateTime(2025, 1, 1)).first;
    final febbraio = await db.budgetDao.watchByMonth(DateTime(2025, 2, 1)).first;

    expect(gennaio.single.amount, 100);
    expect(febbraio.single.amount, 300);
  });

  test('watchByYear restituisce solo i budget dell\'anno richiesto', () async {
    await db.budgetDao.upsertMonthlyBudget(month: DateTime(2024, 12, 1), amount: 900);
    await db.budgetDao.upsertMonthlyBudget(month: DateTime(2025, 1, 1), amount: 1000);
    await db.budgetDao.upsertMonthlyBudget(month: DateTime(2025, 12, 1), amount: 1100);

    final anno2025 = await db.budgetDao.watchByYear(2025).first;

    expect(anno2025.map((b) => b.amount).toList(), [1000, 1100]);
  });

  test('softDelete esclude il budget dalle letture successive', () async {
    final month = DateTime(2025, 6, 1);
    await db.budgetDao.upsertMonthlyBudget(month: month, amount: 500);
    final id = (await db.budgetDao.watchByMonth(month).first).single.id;

    await db.budgetDao.softDelete(id);

    final rows = await db.budgetDao.watchByMonth(month).first;
    expect(rows, isEmpty);
  });
}
