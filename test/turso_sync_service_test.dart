import 'dart:async';

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
    // Fissato ed esplicitamente vecchio (non il default `currentDateAndTime`
    // di SQLite, a risoluzione di secondo): un successivo softDelete() che
    // imposta `updatedAt: DateTime.now()` deve risultare sempre più recente,
    // senza ambiguità legate alla risoluzione dell'orologio nei test veloci.
    DateTime? updatedAt,
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
            updatedAt: Value(updatedAt ?? DateTime(2020, 1, 1)),
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

  test(
    'syncNow concorrenti: una chiamata che arriva mentre una è già in corso '
    'non si accontenta del suo risultato, ne aspetta una fresca che include '
    'le modifiche fatte nel frattempo',
    () async {
      // Blocca la prima sync "a metà" (dentro la sua prima execute()), per
      // simulare una sync di sfondo già partita ma non ancora finita.
      final gate = Completer<void>();
      fakeClient.blockUntil = gate.future;

      final firstSync = sync.syncNow();

      // Una seconda chiamata concorrente, come farebbe un hard delete in
      // Admin subito dopo un soft delete mentre una sync di sfondo gira già.
      final secondSync = sync.syncNow();
      // Lascia girare l'event loop così la seconda chiamata entra davvero
      // nel ramo "aspetta quella in corso" prima di sbloccare la prima.
      await Future.delayed(Duration.zero);

      // Solo ORA, dopo che entrambe le chiamate sono partite, arriva una
      // modifica locale: la prima sync (già bloccata dentro la sua execute)
      // non può averla fotografata; solo una sync fresca, avviata dopo,
      // può includerla.
      await insertLocalTransaction(syncId: 'tardiva', amount: 9.99, note: 'Tardiva');

      gate.complete();
      await Future.wait([firstSync, secondSync]);

      expect(fakeClient.tables['sync_transactions']?['tardiva'], isNotNull,
          reason: 'la seconda chiamata a syncNow() deve aver lanciato un giro '
              'fresco che include la transazione scritta dopo la prima chiamata, '
              'non essersi accontentata del giro già in corso');
    },
  );

  group('isTransactionDeletionConfirmedRemotely', () {
    test('true se Turso non è configurato (client iniettato ma senza credenziali reali non è il caso qui: verifichiamo il caso "mai sincronizzata")', () async {
      final id = await insertLocalTransaction(syncId: 'mai-sincronizzata');
      // Nessun syncNow() eseguito: il server non ha mai visto questa riga.
      expect(await sync.isTransactionDeletionConfirmedRemotely(id), isTrue);
    });

    test('true se il server conferma is_deleted = 1', () async {
      final id = await insertLocalTransaction(syncId: 'confermata');
      await sync.syncNow();
      await db.transactionDao.softDelete(id);
      await sync.syncNow();

      expect(await sync.isTransactionDeletionConfirmedRemotely(id), isTrue);
    });

    test('false se il server ha ancora is_deleted = 0 (sync non ancora avvenuta dopo il soft delete)', () async {
      final id = await insertLocalTransaction(syncId: 'non-ancora');
      await sync.syncNow(); // la riga arriva sul server, ma non cancellata
      await db.transactionDao.softDelete(id); // soft delete locale, MAI sincronizzato

      expect(await sync.isTransactionDeletionConfirmedRemotely(id), isFalse);
    });
  });
}
