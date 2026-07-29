import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/services/google_sheets_credentials_store.dart';
import '../../data/services/google_sheets_row_formatter.dart';
import '../../data/services/google_sheets_service.dart';
import '../../domain/entities/transaction_entity.dart';
import 'category_providers.dart';
import 'database_provider.dart';

const _enabledKey = 'google_sheets_enabled';
const _spreadsheetIdKey = 'google_sheets_spreadsheet_id';
const _sheetNameKey = 'google_sheets_sheet_name';
const googleSheetsSheetNameDefault = 'Copia di Spese';

final googleSheetsCredentialsStoreProvider =
    Provider<GoogleSheetsCredentialsStore>((ref) {
  return GoogleSheetsCredentialsStore();
});

final googleSheetsServiceProvider = Provider<GoogleSheetsService>((ref) {
  return const GoogleSheetsService();
});

/// Se il bridge verso il foglio Google "Copia di Spese" è attivo
/// (configurabile solo dalla pagina Admin, v. CLAUDE.md). Stesso pattern
/// key-value su `Settings` già usato per `themeModeProvider`.
final googleSheetsEnabledProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals(_enabledKey)))
      .watchSingleOrNull()
      .map((row) => row?.value == 'true');
});

final setGoogleSheetsEnabledProvider =
    Provider<Future<void> Function(bool)>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (value) => db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: _enabledKey,
          value: value.toString(),
          updatedAt: Value(DateTime.now()),
        ),
      );
});

final googleSheetsSpreadsheetIdProvider = StreamProvider<String>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)
        ..where((s) => s.key.equals(_spreadsheetIdKey)))
      .watchSingleOrNull()
      .map((row) => row?.value ?? '');
});

final setGoogleSheetsSpreadsheetIdProvider =
    Provider<Future<void> Function(String)>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (value) => db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: _spreadsheetIdKey,
          value: value,
          updatedAt: Value(DateTime.now()),
        ),
      );
});

final googleSheetsSheetNameProvider = StreamProvider<String>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals(_sheetNameKey)))
      .watchSingleOrNull()
      .map((row) => row?.value ?? googleSheetsSheetNameDefault);
});

final setGoogleSheetsSheetNameProvider =
    Provider<Future<void> Function(String)>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (value) => db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: _sheetNameKey,
          value: value,
          updatedAt: Value(DateTime.now()),
        ),
      );
});

/// Invia in background una copia di [transaction] al foglio Google, se il
/// bridge è attivo e configurato (v. `addTransactionProvider`).
///
/// Fallimenti isolati: non rilancia l'eccezione, così un problema di
/// rete/permessi su Sheets non blocca né fa fallire il salvataggio locale
/// della transazione — stesso principio di isolamento errori già seguito
/// per la sync Turso.
Future<void> pushTransactionToGoogleSheet(
  Ref ref,
  TransactionEntity transaction,
) async {
  try {
    final enabled = await ref.read(googleSheetsEnabledProvider.future);
    if (!enabled) return;

    final credentials =
        await ref.read(googleSheetsCredentialsStoreProvider).read();
    final spreadsheetId =
        await ref.read(googleSheetsSpreadsheetIdProvider.future);
    if (credentials == null || credentials.isEmpty || spreadsheetId.isEmpty) {
      return;
    }
    final sheetName = await ref.read(googleSheetsSheetNameProvider.future);

    final categoryDao = ref.read(categoryDaoProvider);
    final category =
        await categoryDao.getCategoryById(transaction.categoryId);
    final subCategory = transaction.subCategoryId == null
        ? null
        : await categoryDao.getSubCategoryById(transaction.subCategoryId!);

    final row = GoogleSheetsRowFormatter.format(
      transaction: transaction,
      categoryName: category?.name ?? '',
      subCategoryName: subCategory?.name ?? '',
    );

    await ref.read(googleSheetsServiceProvider).appendRow(
          serviceAccountJson: credentials,
          spreadsheetId: spreadsheetId,
          sheetName: sheetName,
          row: row,
        );
  } catch (e) {
    debugPrint('Errore invio transazione a Google Sheet: $e');
  }
}
