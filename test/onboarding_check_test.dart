import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/seed/onboarding_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `resolveNeedsOnboarding` (M49): logica pura del wizard di primo
/// avvio, isolata dalla UI e da Riverpod — stesso principio degli altri
/// test su `data/local/seed/`.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> insertCategoria() {
    return db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Spesa',
            icon: '🛒',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
  }

  Future<void> insertTransazione(int categoryId) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            date: DateTime(2026, 9, 1),
            amount: 10,
            type: TransactionKind.expense,
            categoryId: categoryId,
          ),
        );
  }

  group('resolveNeedsOnboarding', () {
    test('installazione vuota, Turso non configurato: true', () async {
      final result = await resolveNeedsOnboarding(
        db,
        isTursoConfigured: () async => false,
      );
      expect(result, isTrue);
    });

    test('installazione vuota ma Turso già configurato: false, e marca '
        'completato in silenzio (backfill)', () async {
      final result = await resolveNeedsOnboarding(
        db,
        isTursoConfigured: () async => true,
      );
      expect(result, isFalse);

      final row = await (db.select(db.settings)
            ..where((s) => s.key.equals(onboardingCompletedSettingsKey)))
          .getSingleOrNull();
      expect(row?.value, 'true');
    });

    test('esiste già almeno una transazione: false, backfill', () async {
      final categoryId = await insertCategoria();
      await insertTransazione(categoryId);

      final result = await resolveNeedsOnboarding(
        db,
        isTursoConfigured: () async => false,
      );
      expect(result, isFalse);

      final row = await (db.select(db.settings)
            ..where((s) => s.key.equals(onboardingCompletedSettingsKey)))
          .getSingleOrNull();
      expect(row?.value, 'true');
    });

    test('onboarding già marcato completato: false, senza richiamare '
        'isTursoConfigured', () async {
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: onboardingCompletedSettingsKey,
              value: 'true',
              updatedAt: Value(DateTime.now()),
            ),
          );

      var isTursoConfiguredCalled = false;
      final result = await resolveNeedsOnboarding(
        db,
        isTursoConfigured: () async {
          isTursoConfiguredCalled = true;
          return false;
        },
      );
      expect(result, isFalse);
      expect(isTursoConfiguredCalled, isFalse);
    });
  });
}
