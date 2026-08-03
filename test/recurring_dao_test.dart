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
    int? totalOccurrences,
    int occurrencesGenerated = 0,
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
        totalOccurrences: Value(totalOccurrences),
        occurrencesGenerated: Value(occurrencesGenerated),
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

  group('numero di occorrenze finito', () {
    test('senza totalOccurrences (null) il comportamento resta indeterminato come prima', () async {
      final today = DateTime(2025, 6, 10);
      final id = await insertRecurring(nextOccurrence: today);

      await db.recurringDao.generateDue(today);

      final updated = await db.recurringDao.getById(id);
      expect(updated!.active, isTrue);
      expect(updated.occurrencesGenerated, 1);
    });

    test('genera fino al numero impostato, poi si mette in pausa da sola', () async {
      final today = DateTime(2025, 6, 10);
      final id = await insertRecurring(nextOccurrence: today, totalOccurrences: 2);

      final firstRun = await db.recurringDao.generateDue(today);
      expect(firstRun, 1);
      var updated = await db.recurringDao.getById(id);
      expect(updated!.active, isTrue);
      expect(updated.occurrencesGenerated, 1);

      final secondRun = await db.recurringDao.generateDue(today.add(const Duration(days: 7)));
      expect(secondRun, 1);
      updated = await db.recurringDao.getById(id);
      expect(updated!.active, isFalse, reason: 'raggiunte le 2 occorrenze impostate, deve fermarsi da sola');
      expect(updated.occurrencesGenerated, 2);

      // Un'ulteriore chiamata non deve generare altro: la ricorrenza è già
      // in pausa (active=false), quindi non viene nemmeno selezionata.
      final thirdRun = await db.recurringDao.generateDue(today.add(const Duration(days: 14)));
      expect(thirdRun, 0);
    });

    test('il recupero di più occorrenze arretrate non supera il numero massimo impostato', () async {
      final today = DateTime(2025, 6, 10);
      // 3 periodi settimanali di ritardo: senza il tetto genererebbe 4 occorrenze.
      final id = await insertRecurring(
        nextOccurrence: today.subtract(const Duration(days: 21)),
        totalOccurrences: 2,
      );

      final generated = await db.recurringDao.generateDue(today);

      expect(generated, 2, reason: 'si ferma al tetto anche recuperando più arretrati insieme');
      final updated = await db.recurringDao.getById(id);
      expect(updated!.occurrencesGenerated, 2);
      expect(updated.active, isFalse);

      final createdTransactions = await (db.select(db.transactions)
            ..where((t) => t.recurringId.equals(id)))
          .get();
      expect(createdTransactions, hasLength(2));
    });

    test('riprende da dove era rimasta se il tetto viene alzato e riattivata a mano', () async {
      final today = DateTime(2025, 6, 10);
      final id = await insertRecurring(
        nextOccurrence: today,
        totalOccurrences: 1,
      );
      await db.recurringDao.generateDue(today);
      var updated = await db.recurringDao.getById(id);
      expect(updated!.active, isFalse);

      // L'utente alza il tetto e riattiva manualmente (v. RecurringEditPage).
      // .write() invece di updateRecurring/.replace(): qui serve un update
      // parziale, non una sostituzione completa della riga.
      await (db.update(db.recurringTransactions)..where((r) => r.id.equals(id)))
          .write(const RecurringTransactionsCompanion(
        totalOccurrences: Value(3),
        active: Value(true),
      ));

      final generated = await db.recurringDao.generateDue(today.add(const Duration(days: 7)));
      expect(generated, 1);
      updated = await db.recurringDao.getById(id);
      expect(updated!.occurrencesGenerated, 2);
      expect(updated.active, isTrue);
    });
  });
}
