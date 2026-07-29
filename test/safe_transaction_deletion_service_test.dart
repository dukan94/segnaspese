import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/services/safe_transaction_deletion_service.dart';
import 'package:finance_app/data/services/turso_sync_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_turso_http_client.dart';

void main() {
  late AppDatabase db;
  late FakeTursoHttpClient fakeClient;
  late TursoSyncService sync;
  late int categoryId;

  Future<int> insertTransazione({required String syncId, bool isDeleted = false}) {
    return db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            date: DateTime(2026, 7, 1),
            amount: 10,
            type: TransactionKind.expense,
            categoryId: categoryId,
            syncId: Value(syncId),
            isDeleted: Value(isDeleted),
            updatedAt: Value(DateTime(2020, 1, 1)),
          ),
        );
  }

  setUp(() async {
    // Test double ufficiale del pacchetto: evita di dover inizializzare un
    // binding Flutter/platform channel solo per isConfigured()/configure().
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fakeClient = FakeTursoHttpClient();
    sync = TursoSyncService(db, client: fakeClient, secureStorage: const FlutterSecureStorage());
    categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Spesa',
            icon: '🛒',
            type: TransactionKind.expense,
            color: 0xFF000000,
            syncId: const Value('cat-1'),
          ),
        );
  });

  tearDown(() {
    sync.dispose();
    db.close();
  });

  group('Turso non configurato', () {
    test('hardDeleteTransaction elimina subito, senza verifiche remote', () async {
      final id = await insertTransazione(syncId: 'a');
      final service = SafeTransactionDeletionService(db.transactionDao, sync);

      final outcome = await service.hardDeleteTransaction(id);

      expect(outcome.deleted, isTrue);
      final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(row, isNull);
    });

    test('purgeSoftDeletedTransactions elimina tutte le già soft-deleted', () async {
      final deletedId = await insertTransazione(syncId: 'a', isDeleted: true);
      final activeId = await insertTransazione(syncId: 'b');
      final service = SafeTransactionDeletionService(db.transactionDao, sync);

      final outcome = await service.purgeSoftDeletedTransactions();

      expect(outcome.purgedCount, 1);
      expect(outcome.skippedCount, 0);
      final deletedRow = await (db.select(db.transactions)..where((t) => t.id.equals(deletedId))).getSingleOrNull();
      expect(deletedRow, isNull);
      final activeRow = await (db.select(db.transactions)..where((t) => t.id.equals(activeId))).getSingleOrNull();
      expect(activeRow != null, true);
    });
  });

  group('Turso configurato', () {
    Future<void> configure() async {
      // NON tramite sync.configure(): sovrascriverebbe il client iniettato
      // (fakeClient) con un TursoHttpClient vero. Scriviamo direttamente le
      // stesse chiavi lette da isConfigured()/_ensureClient(), così il
      // client HTTP resta quello finto.
      const storage = FlutterSecureStorage();
      await storage.write(key: 'turso_url', value: 'https://fake');
      await storage.write(key: 'turso_auth_token', value: 'token');
    }

    test('hardDeleteTransaction elimina per sempre quando il server conferma', () async {
      await configure();
      final id = await insertTransazione(syncId: 'confermabile');
      final service = SafeTransactionDeletionService(
        db.transactionDao,
        sync,
        retryDelay: Duration.zero,
      );

      final outcome = await service.hardDeleteTransaction(id);

      expect(outcome.deleted, isTrue, reason: outcome.reason ?? '');
      final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(row, isNull);
      expect(fakeClient.tables['sync_transactions']?['confermabile']?['is_deleted'], 1);
    });

    test('hardDeleteTransaction NON elimina se il server non conferma mai (push che continua a fallire)', () async {
      await configure();
      final id = await insertTransazione(syncId: 'irraggiungibile');
      fakeClient.failTableContaining = 'sync_transactions';
      final service = SafeTransactionDeletionService(
        db.transactionDao,
        sync,
        maxSyncAttempts: 2,
        retryDelay: Duration.zero,
      );

      final outcome = await service.hardDeleteTransaction(id);

      expect(outcome.deleted, isFalse);
      expect(outcome.reason, isNotNull);
      // Resta soft-deleted (nascosta) ma NON eliminata per sempre.
      final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
    });

    test(
      'purgeSoftDeletedTransactions elimina subito una riga mai sincronizzata (nessuna copia remota da temere)',
      () async {
        await configure();
        // Categoria SENZA syncId: come dati legacy mai sincronizzati.
        // _pushTransactions scarta questa transazione in silenzio (v.
        // `if (categorySyncId == null) continue;`), ma è comunque sicuro
        // eliminarla per sempre: il server non ne ha mai avuto copia, quindi
        // non c'è nulla che possa "ricomparire".
        final orphanCategoryId = await db.into(db.categories).insert(
              CategoriesCompanion.insert(
                name: 'Categoria mai sincronizzata',
                icon: '❓',
                type: TransactionKind.expense,
                color: 0xFF000000,
              ),
            );
        final neverSyncedId = await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                date: DateTime(2026, 7, 1),
                amount: 10,
                type: TransactionKind.expense,
                categoryId: orphanCategoryId,
                syncId: const Value('mai-vista-dal-server'),
                isDeleted: const Value(true),
                updatedAt: Value(DateTime(2020, 1, 1)),
              ),
            );
        final service = SafeTransactionDeletionService(db.transactionDao, sync, retryDelay: Duration.zero);

        final outcome = await service.purgeSoftDeletedTransactions();

        expect(outcome.purgedCount, 1);
        expect(outcome.skippedCount, 0);
        final row = await (db.select(db.transactions)..where((t) => t.id.equals(neverSyncedId))).getSingleOrNull();
        expect(row, null);
      },
    );

    test(
      'purgeSoftDeletedTransactions salta una riga che il server mostra ancora attiva '
      '(pareggio di updated_at: né push né pull la aggiornano, un vero stallo)',
      () async {
        await configure();
        final sameUpdatedAt = DateTime(2020, 1, 1); // stesso default di insertTransazione()
        final confirmable = await insertTransazione(syncId: 'purge-ok', isDeleted: true);
        final stuck = await insertTransazione(syncId: 'purge-stuck', isDeleted: true);

        // Il server ha già una copia di "purge-stuck", ATTIVA (is_deleted=0),
        // con lo STESSO updated_at della riga locale: né il push (serve
        // `excluded.updated_at > sync_transactions.updated_at`) né il pull
        // (serve `updatedAt.isAfter(existing.updatedAt)`) applicano un
        // pareggio — la riga resta bloccata su entrambi i lati, un vero
        // stallo che solo la verifica sul server può intercettare.
        fakeClient.tables['sync_transactions'] = {
          'purge-stuck': {
            'sync_id': 'purge-stuck',
            'date': DateTime(2026, 7, 1).millisecondsSinceEpoch,
            'amount': 10.0,
            'type': TransactionKind.expense.index,
            'category_sync_id': 'cat-1',
            'sub_category_sync_id': null,
            'note': null,
            'is_extraordinary': 0,
            'is_refund': 0,
            'recurring_sync_id': null,
            'refund_of_sync_id': null,
            'updated_at': sameUpdatedAt.millisecondsSinceEpoch,
            'is_deleted': 0,
          },
        };

        final service = SafeTransactionDeletionService(db.transactionDao, sync, retryDelay: Duration.zero);

        final outcome = await service.purgeSoftDeletedTransactions();

        expect(outcome.purgedCount, 1);
        expect(outcome.skippedCount, 1);
        final okRow = await (db.select(db.transactions)..where((t) => t.id.equals(confirmable))).getSingleOrNull();
        expect(okRow, null);
        final stuckRow = await (db.select(db.transactions)..where((t) => t.id.equals(stuck))).getSingleOrNull();
        expect(stuckRow, isNotNull,
            reason: 'il server la mostra ancora attiva: non va eliminata per sempre');
        expect(stuckRow!.isDeleted, isTrue, reason: 'resta soft-deleted localmente, solo non purgata per sempre');
      },
    );
  });
}
