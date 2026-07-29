import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/database/tables/recurring_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int categoryId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Abbonamenti',
            icon: '📺',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> insertRecurring({
    required DateTime nextOccurrence,
    RecurringFrequency frequency = RecurringFrequency.weekly,
    int? dayOfMonth,
    bool active = true,
    bool isDeleted = false,
  }) {
    return db.recurringDao.insertRecurring(
      RecurringTransactionsCompanion.insert(
        description: 'Netflix',
        amount: 12.99,
        type: TransactionKind.expense,
        categoryId: categoryId,
        frequency: frequency,
        dayOfMonth: Value(dayOfMonth),
        nextOccurrence: nextOccurrence,
        active: Value(active),
        isDeleted: Value(isDeleted),
      ),
    );
  }

  test('ricorrenza settimanale dovuta oggi: genera 1 transazione e avanza di 7 giorni', () async {
    final today = DateTime(2025, 6, 10);
    final id = await insertRecurring(nextOccurrence: today);

    final generated = await db.recurringDao.generateDue(today);

    expect(generated, 1);
    final updated = await db.recurringDao.getById(id);
    expect(updated!.nextOccurrence, DateTime(2025, 6, 17));
  });

  test('recupera più occorrenze arretrate se l\'app non era aperta da tempo', () async {
    final today = DateTime(2025, 6, 10);
    // 2 periodi settimanali di ritardo rispetto a oggi.
    final id = await insertRecurring(nextOccurrence: today.subtract(const Duration(days: 14)));

    final generated = await db.recurringDao.generateDue(today);

    // Le occorrenze arretrate (-14, -7) più quella corrente (oggi) sono tutte dovute.
    expect(generated, 3);
    final updated = await db.recurringDao.getById(id);
    expect(updated!.nextOccurrence, DateTime(2025, 6, 17));

    final createdTransactions = await (db.select(db.transactions)
          ..where((t) => t.recurringId.equals(id)))
        .get();
    expect(createdTransactions, hasLength(3));
  });

  test('mensile: giorno 31 su un mese più corto viene ridotto all\'ultimo giorno (28 feb non bisestile)', () async {
    final id = await insertRecurring(
      nextOccurrence: DateTime(2025, 1, 31),
      frequency: RecurringFrequency.monthly,
      dayOfMonth: 31,
    );

    await db.recurringDao.generateDue(DateTime(2025, 1, 31));

    final updated = await db.recurringDao.getById(id);
    expect(updated!.nextOccurrence, DateTime(2025, 2, 28));
  });

  test('annuale: 29 febbraio su anno bisestile diventa 28 febbraio l\'anno dopo', () async {
    final id = await insertRecurring(
      nextOccurrence: DateTime(2024, 2, 29),
      frequency: RecurringFrequency.yearly,
    );

    await db.recurringDao.generateDue(DateTime(2024, 2, 29));

    final updated = await db.recurringDao.getById(id);
    expect(updated!.nextOccurrence, DateTime(2025, 2, 28));
  });

  test('ricorrenza in pausa (active=false) non genera nulla', () async {
    final id = await insertRecurring(nextOccurrence: DateTime(2025, 6, 10), active: false);

    final generated = await db.recurringDao.generateDue(DateTime(2025, 6, 10));

    expect(generated, 0);
    final updated = await db.recurringDao.getById(id);
    expect(updated!.nextOccurrence, DateTime(2025, 6, 10));
  });

  test('ricorrenza cancellata (isDeleted=true) non genera nulla', () async {
    await insertRecurring(nextOccurrence: DateTime(2025, 6, 10), isDeleted: true);

    final generated = await db.recurringDao.generateDue(DateTime(2025, 6, 10));

    expect(generated, 0);
  });

  test('ricorrenza non ancora dovuta: nessuna transazione, nextOccurrence invariata', () async {
    final future = DateTime(2025, 12, 25);
    final id = await insertRecurring(nextOccurrence: future);

    final generated = await db.recurringDao.generateDue(DateTime(2025, 6, 10));

    expect(generated, 0);
    final updated = await db.recurringDao.getById(id);
    expect(updated!.nextOccurrence, future);
  });
}
