import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migrazione locale interrotta (bug reale 16 ago 2026)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('app_database_migration_test');
      dbFile = File('${tempDir.path}/finance_app.sqlite');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
        'apre senza eccezioni un DB con le colonne v7 già presenti ma '
        'user_version rimasto a 6 (migrazione interrotta a metà)', () async {
      // Simula uno storico d'installazione reale: crea prima un DB v7
      // completo (onCreate), poi riporta indietro SOLO user_version a 6 —
      // esattamente lo stato lasciato da un processo ucciso a metà della
      // migrazione v7 su una macchina reale: la ALTER TABLE era già
      // andata a buon fine, ma Drift non aveva ancora scritto la nuova
      // versione dello schema.
      final seedDb = AppDatabase.forTesting(NativeDatabase(dbFile));
      await seedDb.customSelect('SELECT 1').get();
      await seedDb.customStatement('PRAGMA user_version = 6');
      await seedDb.close();

      // Prima del fix: qui Drift rilancia gli addColumn di onUpgrade(6, 7)
      // su colonne già esistenti → SqliteException("duplicate column
      // name"). Con la guardia _columnExists, deve aprirsi pulito.
      final reopened = AppDatabase.forTesting(NativeDatabase(dbFile));
      await expectLater(reopened.customSelect('SELECT 1').get(), completes);

      final versionRows =
          await reopened.customSelect('PRAGMA user_version').get();
      // schemaVersion corrente (era 7 quando questo test è stato scritto per
      // il bug M17; aggiornato a 8 con la rimozione della tabella Merchants,
      // M35 — lo scenario/la guardia testata restano gli stessi).
      expect(versionRows.single.data['user_version'], 8);

      await reopened.close();
    });
  });

  group('rimozione tabella Merchants (M35, 17 ago 2026)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('app_database_merchants_test');
      dbFile = File('${tempDir.path}/finance_app.sqlite');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
        'apre senza eccezioni un DB v7 reale con Merchants popolata e '
        'merchantId valorizzato, e le rimuove entrambe senza perdere le '
        'altre colonne della transazione', () async {
      // Crea uno schema v8 pulito (quello corrente, già senza Merchants),
      // poi ricostruisce sopra la tabella Merchants e la colonna
      // merchantId esattamente come nello schema v7 storico (stesso
      // vincolo FK) — replica lo stato reale di un dispositivo mai ancora
      // aggiornato a questa versione, non un DB creato "già pulito".
      final seedDb = AppDatabase.forTesting(NativeDatabase(dbFile));
      final categoryId = await seedDb.into(seedDb.categories).insert(
            CategoriesCompanion.insert(
              name: 'Casa',
              icon: '🏠',
              type: TransactionKind.expense,
              color: 0xFF000000,
            ),
          );
      final txId = await seedDb.into(seedDb.transactions).insert(
            TransactionsCompanion.insert(
              date: DateTime(2026, 1, 1),
              amount: 42.5,
              type: TransactionKind.expense,
              categoryId: categoryId,
              note: const Value('spesa di prova'),
            ),
          );

      await seedDb.customStatement('''
        CREATE TABLE merchants (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          default_category_id INTEGER REFERENCES categories(id),
          default_sub_category_id INTEGER,
          updated_at INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          sync_id TEXT
        )
      ''');
      await seedDb.customStatement(
          "INSERT INTO merchants (id, name, updated_at) VALUES (1, 'Esselunga', 0)");
      await seedDb.customStatement(
          'ALTER TABLE transactions ADD COLUMN merchant_id INTEGER REFERENCES merchants(id)');
      await seedDb.customStatement(
          'UPDATE transactions SET merchant_id = 1 WHERE id = ?', [txId]);
      await seedDb.customStatement('PRAGMA user_version = 7');
      await seedDb.close();

      // Riapertura con lo schema corrente: deve rimuovere merchantId (via
      // TableMigration, dato che DROP COLUMN diretto non è possibile su una
      // colonna con vincolo FK) e droppare Merchants, senza eccezioni.
      final reopened = AppDatabase.forTesting(NativeDatabase(dbFile));
      await expectLater(reopened.customSelect('SELECT 1').get(), completes);

      final txCols =
          await reopened.customSelect('PRAGMA table_info(transactions)').get();
      expect(txCols.any((r) => r.data['name'] == 'merchant_id'), isFalse);

      final merchantsTable = await reopened
          .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='merchants'")
          .get();
      expect(merchantsTable, isEmpty);

      // Le altre colonne della transazione sopravvivono intatte alla
      // ricreazione della tabella.
      final rows = await reopened.select(reopened.transactions).get();
      expect(rows, hasLength(1));
      expect(rows.single.note, 'spesa di prova');
      expect(rows.single.amount, 42.5);
      expect(rows.single.categoryId, categoryId);

      final versionRows =
          await reopened.customSelect('PRAGMA user_version').get();
      expect(versionRows.single.data['user_version'], 8);

      await reopened.close();
    });

    test(
        'riaprire due volte di seguito (migrazione già applicata) non '
        'lancia eccezioni — idempotenza', () async {
      final seedDb = AppDatabase.forTesting(NativeDatabase(dbFile));
      await seedDb.customSelect('SELECT 1').get();
      await seedDb.close();

      final firstReopen = AppDatabase.forTesting(NativeDatabase(dbFile));
      await firstReopen.customSelect('SELECT 1').get();
      await firstReopen.close();

      final secondReopen = AppDatabase.forTesting(NativeDatabase(dbFile));
      await expectLater(secondReopen.customSelect('SELECT 1').get(), completes);
      await secondReopen.close();
    });
  });
}
