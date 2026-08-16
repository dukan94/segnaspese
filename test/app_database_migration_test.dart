import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('migrazione locale interrotta (bug reale 16 ago 2026)', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_database_migration_test');
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
      expect(versionRows.single.data['user_version'], 7);

      await reopened.close();
    });
  });
}
