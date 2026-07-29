import 'dart:convert';

import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart' as auth;

/// Scrittura di righe sul foglio Google Sheet "Copia di Spese" (bridge
/// temporaneo, v. CLAUDE.md sezione Admin).
///
/// Autenticazione via service account, non OAuth interattivo:
/// `google_sign_in` non supporta Windows desktop, e questa app gira da
/// un'unica codebase su Windows e Android. Nessun login: il service account
/// viene condiviso come Editor sul foglio specifico, fuori dall'app.
class GoogleSheetsService {
  const GoogleSheetsService();

  static const _scopes = [sheets.SheetsApi.spreadsheetsScope];

  /// Estrae l'id dello spreadsheet da un URL Google Sheets incollato
  /// dall'utente, o lo restituisce invariato se è già un id nudo.
  static String extractSpreadsheetId(String input) {
    final match = RegExp(r'/d/([a-zA-Z0-9-_]+)').firstMatch(input);
    return (match?.group(1) ?? input).trim();
  }

  Future<auth.AutoRefreshingAuthClient> _client(
    String serviceAccountJson,
  ) {
    final credentials = auth.ServiceAccountCredentials.fromJson(
      jsonDecode(serviceAccountJson) as Map<String, dynamic>,
    );
    return auth.clientViaServiceAccount(credentials, _scopes);
  }

  /// Aggiunge [row] in fondo al tab [sheetName]. Alza eccezione in caso di
  /// errore: il chiamante (v. core/di/google_sheets_providers.dart) decide
  /// come isolarlo, così un problema di rete/permessi qui non blocca né fa
  /// fallire il salvataggio locale della transazione.
  Future<void> appendRow({
    required String serviceAccountJson,
    required String spreadsheetId,
    required String sheetName,
    required List<String> row,
  }) async {
    final client = await _client(serviceAccountJson);
    try {
      final api = sheets.SheetsApi(client);
      await api.spreadsheets.values.append(
        sheets.ValueRange(values: [row]),
        spreadsheetId,
        "'$sheetName'",
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    } finally {
      client.close();
    }
  }

  /// Verifica solo che credenziali/id/nome tab siano validi e accessibili,
  /// senza scrivere nulla (pulsante "Testa connessione" in Admin).
  Future<void> testConnection({
    required String serviceAccountJson,
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final client = await _client(serviceAccountJson);
    try {
      final api = sheets.SheetsApi(client);
      final spreadsheet = await api.spreadsheets.get(spreadsheetId);
      final exists =
          spreadsheet.sheets?.any((s) => s.properties?.title == sheetName) ??
              false;
      if (!exists) {
        throw Exception('Nessun tab chiamato "$sheetName" in questo foglio');
      }
    } finally {
      client.close();
    }
  }
}
