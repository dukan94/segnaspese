import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/services/turso_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_turso_http_client.dart';

void main() {
  late AppDatabase db;
  late FakeTursoHttpClient fakeClient;
  late TursoSyncService sync;
  late int categoryId;
  late int subCategoryId;
  const categorySyncId = 'cat-sync-1';
  const subCategorySyncId = 'sub-sync-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fakeClient = FakeTursoHttpClient();
    sync = TursoSyncService(db, client: fakeClient);

    categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Fuori Casa',
            icon: '🍔',
            type: TransactionKind.expense,
            color: 0xFF000000,
            syncId: const Value(categorySyncId),
          ),
        );
    subCategoryId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(
            categoryId: categoryId,
            name: 'Ristorante / Uscita',
            syncId: const Value(subCategorySyncId),
          ),
        );
  });

  tearDown(() {
    sync.dispose();
    db.close();
  });

  Future<int> insertLocalTransaction({
    required String syncId,
    DateTime? date,
    double amount = 25.0,
    String? note = 'Cena',
    bool isRefund = false,
  }) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            date: date ?? DateTime(2026, 7, 24),
            amount: amount,
            type: TransactionKind.expense,
            categoryId: categoryId,
            subCategoryId: Value(subCategoryId),
            note: Value(note),
            isRefund: Value(isRefund),
            syncId: Value(syncId),
          ),
        );
  }

  test('push: una transazione locale con syncId arriva sul remoto', () async {
    await insertLocalTransaction(syncId: 'local-1', amount: 42.5, note: 'Test push');

    await sync.syncNow();

    final remoteRow = fakeClient.tables['sync_transactions']?['local-1'];
    expect(remoteRow, isNotNull);
    expect(remoteRow!['amount'], 42.5);
    expect(remoteRow['note'], 'Test push');
    expect(remoteRow['category_sync_id'], categorySyncId);
  });

  test('pull: una transazione remota mai vista viene inserita in locale', () async {
    final updatedAt = DateTime(2026, 7, 25).millisecondsSinceEpoch;
    fakeClient.tables['sync_transactions'] = {
      'remote-1': {
        'sync_id': 'remote-1',
        'date': DateTime(2026, 7, 20).millisecondsSinceEpoch,
        'amount': 18.0,
        'type': TransactionKind.expense.index,
        'category_sync_id': categorySyncId,
        'sub_category_sync_id': subCategorySyncId,
        'note': 'Dal server',
        'is_extraordinary': 0,
        'is_refund': 0,
        'recurring_sync_id': null,
        'refund_of_sync_id': null,
        'updated_at': updatedAt,
        'is_deleted': 0,
      },
    };

    await sync.syncNow();

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.syncId, 'remote-1');
    expect(rows.single.amount, 18.0);
    expect(rows.single.note, 'Dal server');
  });

  test('un errore isolato su una tabella non blocca le altre', () async {
    await insertLocalTransaction(syncId: 'local-1');
    fakeClient.failTableContaining = 'sync_categories';

    await expectLater(sync.syncNow(), throwsA(isA<TursoSyncPartialFailureException>()));

    // Le transazioni devono comunque essere arrivate sul remoto, nonostante
    // categories sia fallita: l'isolamento per tabella deve funzionare.
    expect(fakeClient.tables['sync_transactions']?['local-1'], isNotNull);
  });

  test(
    'un errore isolato riporta esattamente i passi falliti nell\'eccezione',
    () async {
      fakeClient.failTableContaining = 'sync_categories';

      try {
        await sync.syncNow();
        fail('doveva lanciare TursoSyncPartialFailureException');
      } on TursoSyncPartialFailureException catch (e) {
        expect(e.stepErrors.keys, containsAll(['push_categories', 'pull_categories']));
        expect(e.stepErrors.keys, isNot(contains('push_transactions')));
        expect(e.stepErrors.keys, isNot(contains('pull_transactions')));
      }
    },
  );

  test(
    'pull: un movimento remoto identico a uno locale (syncId diverso) non viene duplicato',
    () async {
      await insertLocalTransaction(syncId: 'local-1', amount: 25.0, note: 'Cena');

      final updatedAt = DateTime(2026, 7, 26).millisecondsSinceEpoch;
      fakeClient.tables['sync_transactions'] = {
        'remote-duplicate': {
          'sync_id': 'remote-duplicate',
          'date': DateTime(2026, 7, 24).millisecondsSinceEpoch,
          'amount': 25.0,
          'type': TransactionKind.expense.index,
          'category_sync_id': categorySyncId,
          'sub_category_sync_id': subCategorySyncId,
          'note': 'Cena',
          'is_extraordinary': 0,
          'is_refund': 0,
          'recurring_sync_id': null,
          'refund_of_sync_id': null,
          'updated_at': updatedAt,
          'is_deleted': 0,
        },
      };

      await sync.syncNow();

      final rows = await (db.select(db.transactions)..where((t) => t.isDeleted.equals(false))).get();
      expect(rows, hasLength(1), reason: 'non deve essere inserita una seconda riga locale');
      expect(rows.single.syncId, 'local-1');

      final remoteDuplicate = fakeClient.tables['sync_transactions']!['remote-duplicate']!;
      expect(remoteDuplicate['is_deleted'], 1,
          reason: 'il doppione remoto va segnalato cancellato così converge sugli altri device');
    },
  );
}
