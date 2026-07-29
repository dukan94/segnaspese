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

  /// Ordine di colonna assunto da [GoogleSheetsRowFormatter] — v.
  /// `testConnection`, che verifica che il tab reale rispetti davvero questo
  /// ordine prima di lasciar attivare il bridge (altrimenti le righe
  /// finirebbero silenziosamente nelle colonne sbagliate).
  static const expectedHeader = [
    'Data',
    'Quanto',
    'Sub Categoria',
    'Note',
    'Tipologia Spesa',
    'Categoria',
    'Tipologia',
  ];

  /// Estrae l'id dello spreadsheet da un URL Google Sheets incollato
  /// dall'utente, o lo restituisce invariato se è già un id nudo.
  static String extractSpreadsheetId(String input) {
    final match = RegExp(r'/d/([a-zA-Z0-9-_]+)').firstMatch(input);
    return (match?.group(1) ?? input).trim();
  }

  /// Nome del tab tra apici singoli per la notazione A1, con gli eventuali
  /// apici nel nome raddoppiati (sintassi richiesta da Google Sheets per un
  /// nome che contiene un apice, es. `Spese dell'anno` -> `'Spese dell''anno'`).
  static String _quotedSheetName(String sheetName) {
    return "'${sheetName.replaceAll("'", "''")}'";
  }

  /// true se le prime [expectedHeader.length] colonne di [actualHeader]
  /// (già trim-mate) combaciano nell'ordine atteso. Colonne extra dopo
  /// quelle attese sono ammesse (es. note manuali dell'utente sul foglio).
  static bool headerMatches(List<String> actualHeader) {
    final expectedCount = expectedHeader.length;
    if (actualHeader.length < expectedCount) return false;
    for (var i = 0; i < expectedCount; i++) {
      if (actualHeader[i] != expectedHeader[i]) return false;
    }
    return true;
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
        _quotedSheetName(sheetName),
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    } finally {
      client.close();
    }
  }

  /// Verifica che credenziali/id/nome tab siano validi e accessibili, E che
  /// la riga di intestazione del tab combaci con [expectedHeader] — senza
  /// questo controllo, un ordine di colonne diverso da quello assunto da
  /// [GoogleSheetsRowFormatter] farebbe finire ogni riga scritta dal bridge
  /// nelle colonne sbagliate, senza alcun errore visibile (pulsante "Testa
  /// connessione" in Admin).
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

      final headerRange = await api.spreadsheets.values.get(
        spreadsheetId,
        '${_quotedSheetName(sheetName)}!1:1',
      );
      final actualHeader = (headerRange.values?.isNotEmpty == true
              ? headerRange.values!.first
              : const [])
          .map((v) => v.toString().trim())
          .toList();
      if (!headerMatches(actualHeader)) {
        throw Exception(
          'L\'intestazione del tab non combacia con quella attesa '
          '(${expectedHeader.join(";")}). Trovata: '
          '${actualHeader.isEmpty ? "(vuota)" : actualHeader.join(";")}. '
          'Correggi le colonne del foglio prima di attivare il bridge.',
        );
      }
    } finally {
      client.close();
    }
  }
}
