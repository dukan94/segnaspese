import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/seed/seed_runner.dart';
import 'package:finance_app/data/services/turso_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'fakes/fake_turso_http_client.dart';

/// M52: un dispositivo appena installato (tassonomia di default seedata al
/// primo avvio) che si collega a un database Turso già in uso non deve mai
/// resuscitare sul server categorie/sottocategorie già unite o eliminate da
/// un altro dispositivo (bug reale, 23 set 2026 — v. progettazione M52).
void main() {
  late AppDatabase db;
  late FakeTursoHttpClient fakeClient;
  late TursoSyncService sync;

  // Stessa formula (UUID v5) di `_defaultCategorySyncId` in
  // default_categories_seed.dart: il syncId che QUALUNQUE dispositivo dà
  // alla categoria di default "Casa".
  final casaDefaultSyncId =
      const Uuid().v5(Namespace.url.value, 'segnaspese:category:Casa:expense');

  // Momento (reale, ben dopo il timestamp di seed) in cui un altro
  // dispositivo ha unito/eliminato la categoria di default.
  final mergedAt = DateTime(2026, 8, 2).millisecondsSinceEpoch;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fakeClient = FakeTursoHttpClient();
    sync = TursoSyncService(db, client: fakeClient);
  });

  tearDown(() {
    sync.dispose();
    db.close();
  });

  Map<String, Object?> remoteCategory({
    required String syncId,
    required String name,
    required bool isDeleted,
    bool isDefault = false,
  }) =>
      {
        'sync_id': syncId,
        'name': name,
        'icon': '🏠',
        'type': TransactionKind.expense.index,
        'color': 0xFF8D6E63,
        'is_default': isDefault ? 1 : 0,
        'updated_at': mergedAt,
        'is_deleted': isDeleted ? 1 : 0,
      };

  Future<List<Category>> activeCategoriesNamed(String name) {
    return (db.select(db.categories)
          ..where((c) => c.name.equals(name) & c.isDeleted.equals(false)))
        .get();
  }

  test(
    'A: un default già eliminato sul server resta eliminato anche se il '
    'dispositivo (con dati propri) lo ha appena seedato',
    () async {
      fakeClient.tables['sync_categories'] = {
        casaDefaultSyncId: remoteCategory(
          syncId: casaDefaultSyncId,
          name: 'Casa',
          isDeleted: true,
          isDefault: true,
        ),
      };

      await runSeed(db);
      // Dispositivo con dati propri: la pulizia B non scatta, deve bastare
      // il timestamp di seed vecchio (A) a non sovrascrivere il server.
      final spesa = (await activeCategoriesNamed('Spesa')).single;
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            date: DateTime(2026, 9, 1),
            amount: 10,
            type: TransactionKind.expense,
            categoryId: spesa.id,
            syncId: const Value('tx-1'),
          ));

      await sync.syncNow();

      final remoteCasa = fakeClient.tables['sync_categories']![casaDefaultSyncId]!;
      expect(remoteCasa['is_deleted'], 1,
          reason: 'il push del seed non deve resuscitare la categoria sul server');
      expect(remoteCasa['updated_at'], mergedAt);
      expect(await activeCategoriesNamed('Casa'), isEmpty,
          reason: 'la cancellazione remota deve arrivare anche in locale');
    },
  );

  test(
    'B: primo collegamento di un dispositivo appena installato a un server '
    'già in uso: la tassonomia arriva solo dal server, niente doppioni né '
    'default spinti sul remoto',
    () async {
      // Tassonomia remota sotto syncId diversi da quelli deterministici del
      // seed (es. default creati prima che diventassero deterministici, o
      // categorie ricreate a mano).
      fakeClient.tables['sync_categories'] = {
        'remote-casa': remoteCategory(syncId: 'remote-casa', name: 'Casa', isDeleted: false),
      };
      fakeClient.tables['sync_subcategories'] = {
        'remote-bollette': {
          'sync_id': 'remote-bollette',
          'category_sync_id': 'remote-casa',
          'name': 'Bollette',
          'icon': '🧾',
          'updated_at': mergedAt,
          'is_deleted': 0,
        },
      };

      await runSeed(db);
      await sync.syncNow();

      final casa = await activeCategoriesNamed('Casa');
      expect(casa, hasLength(1), reason: 'nessun doppione default + remota');
      expect(casa.single.syncId, 'remote-casa');

      final localCategories = await db.select(db.categories).get();
      expect(localCategories.map((c) => c.syncId), ['remote-casa'],
          reason: 'i default seedati e mai modificati vanno scartati');
      final localSubs = await db.select(db.subCategories).get();
      expect(localSubs.map((s) => s.syncId), ['remote-bollette']);
      expect(await db.select(db.merchantRules).get(), isEmpty);

      expect(fakeClient.tables['sync_categories']!.keys, ['remote-casa'],
          reason: 'nessun default del dispositivo nuovo deve arrivare sul server');
    },
  );

  test(
    'B non tocca un dispositivo che ha già dati propri (i default restano)',
    () async {
      fakeClient.tables['sync_categories'] = {
        'remote-casa': remoteCategory(syncId: 'remote-casa', name: 'Casa', isDeleted: false),
      };

      await runSeed(db);
      final seededCount = (await db.select(db.categories).get()).length;
      final spesa = (await activeCategoriesNamed('Spesa')).single;
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            date: DateTime(2026, 9, 1),
            amount: 10,
            type: TransactionKind.expense,
            categoryId: spesa.id,
            syncId: const Value('tx-1'),
          ));

      await sync.syncNow();

      expect((await db.select(db.categories).get()).length, seededCount + 1);
    },
  );

  test('server vuoto: i default del primo dispositivo arrivano comunque sul remoto',
      () async {
    await runSeed(db);
    final seededCategories = await db.select(db.categories).get();

    await sync.syncNow();

    expect(fakeClient.tables['sync_categories']!.keys.toSet(),
        seededCategories.map((c) => c.syncId).toSet());
    expect(fakeClient.tables['sync_subcategories'], isNotEmpty);
    expect(fakeClient.tables['sync_merchant_rules'], isNotEmpty);
    expect(await db.select(db.categories).get(), hasLength(seededCategories.length));
  });
}
