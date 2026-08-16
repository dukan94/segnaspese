import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Colonne + righe restituite da una singola istruzione [TursoStatement].
class TursoResult {
  const TursoResult(this.columns, this.rows);

  final List<String> columns;
  final List<List<Object?>> rows;

  /// Righe come mappa colonna → valore, più comoda da consumare lato
  /// chiamante rispetto a liste posizionali.
  List<Map<String, Object?>> asMaps() {
    return [
      for (final row in rows) {for (var i = 0; i < columns.length; i++) columns[i]: row[i]},
    ];
  }
}

/// Una singola istruzione SQL con argomenti posizionali (`?`).
class TursoStatement {
  const TursoStatement(this.sql, [this.args = const []]);

  final String sql;
  final List<Object?> args;
}

class TursoApiException implements Exception {
  TursoApiException(this.message);

  final String message;

  @override
  String toString() => 'TursoApiException: $message';
}

/// Wrapper sottile sull'API HTTP di Turso (Hrana-over-HTTP, endpoint
/// `/v2/pipeline`, v. docs.turso.tech/sdk/http/reference). Traduce statement
/// SQL + argomenti Dart in richieste batch tipizzate e le risposte tipizzate
/// (`{"type":"text","value":...}`) in valori Dart nativi.
///
/// Nessuna dipendenza nativa (a differenza del client ufficiale `libsql_dart`,
/// che richiederebbe un toolchain Rust per compilare codice nativo ad ogni
/// build): solo il pacchetto `http`, puro Dart.
class TursoHttpClient {
  TursoHttpClient({required String baseUrl, required String authToken})
      : _baseUrl = _normalizeBaseUrl(baseUrl),
        _authToken = authToken;

  final String _baseUrl;
  final String _authToken;

  static String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    // L'utente copia tipicamente l'URL "libsql://...": l'API HTTP vuole "https://".
    if (normalized.startsWith('libsql://')) {
      normalized = 'https://${normalized.substring('libsql://'.length)}';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// Esegue tutte le [statements] in un'unica richiesta HTTP (batch), nello
  /// stesso ordine, e restituisce un risultato per statement.
  Future<List<TursoResult>> execute(List<TursoStatement> statements) async {
    if (statements.isEmpty) return const [];

    final body = jsonEncode({
      'requests': [
        for (final stmt in statements)
          {
            'type': 'execute',
            'stmt': {
              'sql': stmt.sql,
              'args': [for (final arg in stmt.args) _encodeArg(arg)],
            },
          },
        {'type': 'close'},
      ],
    });

    final http.Response response;
    try {
      response = await sendRequest(Uri.parse('$_baseUrl/v2/pipeline'), body);
    } on TimeoutException {
      throw TursoApiException('Turso non ha risposto entro 30s.');
    } catch (e) {
      throw TursoApiException('Connessione a Turso fallita: $e');
    }

    if (response.statusCode != 200) {
      throw TursoApiException('Turso HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>;

    final out = <TursoResult>[];
    for (var i = 0; i < statements.length; i++) {
      final entry = results[i] as Map<String, dynamic>;
      if (entry['type'] == 'error') {
        throw TursoApiException('Errore SQL Turso: ${entry['error']}');
      }
      final result = (entry['response'] as Map<String, dynamic>)['result'] as Map<String, dynamic>;
      final cols = (result['cols'] as List<dynamic>)
          .map((c) => (c as Map<String, dynamic>)['name'] as String)
          .toList();
      final rows = (result['rows'] as List<dynamic>)
          .map((row) => (row as List<dynamic>)
              .map((cell) => _decodeCell(cell as Map<String, dynamic>))
              .toList())
          .toList();
      out.add(TursoResult(cols, rows));
    }
    return out;
  }

  /// Esegue la chiamata HTTP vera verso Turso. Isolata in un metodo proprio
  /// (`execute` costruisce/decodifica il payload Hrana, mai la rete
  /// direttamente) per poterla sostituire nei test con un fake — a
  /// differenza di `FakeTursoHttpClient` (che sovrascrive `execute` per
  /// intero, bypassando l'encoding/decoding reale), un fake che sovrascrive
  /// solo questo metodo esercita `_encodeArg`/`_decodeCell`/la struttura
  /// JSON reale (v. `test/turso_http_client_test.dart`).
  ///
  /// Senza timeout, una connessione che resta aperta senza rispondere blocca
  /// syncNow() indefinitamente: dato che le chiamate concorrenti a syncNow()
  /// ora ASPETTANO quella in corso invece di ritornare subito (v.
  /// TursoSyncService.syncNow, fix del 29 lug 2026), una singola richiesta
  /// bloccata farebbe accodare indefinitamente anche ogni sync successiva
  /// (avvio, timer, lifecycle, hard delete da Admin) fino allo scadere di
  /// questo timeout.
  Future<http.Response> sendRequest(Uri uri, String body) {
    return http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $_authToken',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));
  }

  /// Argomenti tipizzati secondo il protocollo Hrana: gli interi sono
  /// serializzati come stringa (per non perdere precisione a 64 bit in JSON),
  /// i float come numero JSON nativo.
  Map<String, Object?> _encodeArg(Object? value) {
    if (value == null) return const {'type': 'null'};
    if (value is int) return {'type': 'integer', 'value': value.toString()};
    if (value is double) return {'type': 'float', 'value': value};
    if (value is bool) return {'type': 'integer', 'value': (value ? 1 : 0).toString()};
    return {'type': 'text', 'value': value.toString()};
  }

  Object? _decodeCell(Map<String, dynamic> cell) {
    switch (cell['type'] as String) {
      case 'null':
        return null;
      case 'integer':
        return int.parse(cell['value'] as String);
      case 'float':
        return (cell['value'] as num).toDouble();
      case 'text':
        return cell['value'] as String;
      case 'blob':
        return cell['base64'] as String;
      default:
        return cell['value'];
    }
  }
}
