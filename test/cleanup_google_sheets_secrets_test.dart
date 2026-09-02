import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/seed/cleanup_google_sheets_secrets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `cleanupGoogleSheetsSecrets` (audit post-M48, 2 set 2026): il
/// bridge Google Sheets è stato rimosso senza ripulire la chiave di
/// servizio già in `flutter_secure_storage` né le righe Settings — questa
/// funzione ripara il gap sui dispositivi che l'avevano già configurato.
void main() {
  late AppDatabase db;
  late FlutterSecureStorage secureStorage;

  const secretKey = 'google_sheets_service_account_json';
  const settingsKeys = [
    'google_sheets_enabled',
    'google_sheets_spreadsheet_id',
    'google_sheets_sheet_name',
  ];

  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    secureStorage = const FlutterSecureStorage();
  });

  tearDown(() => db.close());

  Future<void> seedLeftovers() async {
    await secureStorage.write(key: secretKey, value: '{"type":"service_account"}');
    for (final key in settingsKeys) {
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: key,
              value: 'true',
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  group('cleanupGoogleSheetsSecrets', () {
    test('rimuove la chiave di servizio dal secure storage', () async {
      await seedLeftovers();
      await cleanupGoogleSheetsSecrets(db, secureStorage: secureStorage);
      expect(await secureStorage.read(key: secretKey), isNull);
    });

    test('rimuove tutte e 3 le righe Settings orfane', () async {
      await seedLeftovers();
      await cleanupGoogleSheetsSecrets(db, secureStorage: secureStorage);
      for (final key in settingsKeys) {
        final row = await (db.select(db.settings)
              ..where((s) => s.key.equals(key)))
            .getSingleOrNull();
        expect(row, isNull, reason: '$key dovrebbe essere stata rimossa');
      }
    });

    test('non tocca altre righe Settings non correlate', () async {
      await seedLeftovers();
      await db.into(db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'theme_mode',
              value: 'dark',
              updatedAt: Value(DateTime.now()),
            ),
          );
      await cleanupGoogleSheetsSecrets(db, secureStorage: secureStorage);
      final row = await (db.select(db.settings)
            ..where((s) => s.key.equals('theme_mode')))
          .getSingleOrNull();
      expect(row?.value, 'dark');
    });

    test('innocuo se non c\'è nulla da pulire (nessuna eccezione)', () async {
      await cleanupGoogleSheetsSecrets(db, secureStorage: secureStorage);
    });

    test('idempotente: rilanciarlo due volte non lancia eccezioni', () async {
      await seedLeftovers();
      await cleanupGoogleSheetsSecrets(db, secureStorage: secureStorage);
      await cleanupGoogleSheetsSecrets(db, secureStorage: secureStorage);
      expect(await secureStorage.read(key: secretKey), isNull);
    });
  });
}
