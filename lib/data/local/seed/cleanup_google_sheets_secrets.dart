import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database/app_database.dart';

/// Rimuove le tracce lasciate dal bridge Google Sheets (rimosso del tutto in
/// M48): una chiave di servizio Google ancora valida in
/// `flutter_secure_storage` e 3 righe di configurazione in `Settings`,
/// rimaste orfane e irraggiungibili da qualsiasi UI dopo che il codice che
/// le gestiva è stato cancellato (trovato in audit, 2 set 2026) — proprio
/// l'opposto dell'obiettivo di M48 ("niente di personale cucito addosso
/// all'app condivisa": un segreto residuo è esattamente ciò che non
/// dovrebbe sopravvivere a un eventuale passaggio dell'app ad altre
/// persone). Innocuo se non c'è nulla da pulire (`delete` su una chiave
/// assente non lancia): va bene rilanciarlo ad ogni avvio, stesso principio
/// di `dedupe_default_taxonomy.dart`/`repair_orphaned_subcategories.dart`.
Future<void> cleanupGoogleSheetsSecrets(
  AppDatabase db, {
  FlutterSecureStorage? secureStorage,
}) async {
  final storage = secureStorage ?? const FlutterSecureStorage();
  await storage.delete(key: 'google_sheets_service_account_json');
  await (db.delete(db.settings)
        ..where((s) => s.key.isIn(const [
              'google_sheets_enabled',
              'google_sheets_spreadsheet_id',
              'google_sheets_sheet_name',
            ])))
      .go();
}
