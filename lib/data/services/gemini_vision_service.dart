import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GeminiApiException implements Exception {
  GeminiApiException(this.message);

  final String message;

  @override
  String toString() => 'GeminiApiException: $message';
}

/// Dati estratti dallo scontrino da Gemini. Tutti i campi sono nullable: il
/// modello potrebbe non riconoscere un dato, esattamente come
/// `ReceiptParserService` per il percorso OCR + regex.
class AiReceiptResult {
  const AiReceiptResult({this.merchantName, this.total, this.date});

  final String? merchantName;
  final double? total;
  final DateTime? date;
}

/// Estrae negozio/importo/data da una foto di scontrino usando l'API cloud
/// gratuita di Google Gemini, invece del percorso OCR (ML Kit) + regex.
///
/// Stesso stile HTTP puro (`package:http`) già usato per Turso: nessuna
/// dipendenza nativa aggiuntiva. Richiede una API key personale gratuita
/// (Google AI Studio), configurabile in Impostazioni > "AI per scontrini
/// (Gemini)" e conservata in `flutter_secure_storage` (v.
/// `gemini_api_key_store.dart`), mai in chiaro nel codice.
class GeminiVisionService {
  const GeminiVisionService();

  static const _promptTemplate = '''
Analizza l'immagine di questo scontrino/ricevuta italiano e rispondi SOLO con
un oggetto JSON (nessun testo aggiuntivo), con esattamente queste chiavi:
{"negozio": "nome del negozio o null", "totale": importo totale pagato come numero con il punto come separatore decimale o null, "data": "data dello scontrino in formato YYYY-MM-DD o null"}
Se un dato non è leggibile con certezza, usa null per quel campo invece di
indovinare.''';

  /// Esegue la chiamata HTTP vera verso Gemini. Isolata in un metodo proprio
  /// (non inline in `analyzeReceipt`) per poterla sostituire nei test con un
  /// fake — stesso principio già in uso per `TursoHttpClient.execute`/
  /// `FakeTursoHttpClient` — invece di mockare `package:http` o fare
  /// chiamate di rete vere nei test (v. `test/gemini_vision_service_test.dart`).
  Future<http.Response> sendRequest(Uri uri, String jsonBody) {
    return http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonBody,
        )
        .timeout(const Duration(seconds: 30));
  }

  /// Inferenza sull'immagine [image]. [apiKey] e [model] arrivano dalle
  /// impostazioni (v. `gemini_providers.dart`). Timeout di 30s.
  Future<AiReceiptResult> analyzeReceipt(
    File image, {
    required String apiKey,
    required String model,
  }) async {
    final bytes = await image.readAsBytes();
    final base64Image = base64Encode(bytes);

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'
      '?key=$apiKey',
    );

    final http.Response response;
    try {
      response = await sendRequest(
        uri,
        jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': _promptTemplate},
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  },
                },
              ],
            },
          ],
          'generationConfig': {'response_mime_type': 'application/json'},
        }),
      );
    } on TimeoutException {
      throw GeminiApiException('Gemini non ha risposto entro 30s.');
    } on SocketException {
      throw GeminiApiException(
          'Impossibile contattare Gemini: nessuna connessione di rete.');
    } catch (e) {
      // MAI interpolare l'eccezione originale nel messaggio (bug reale,
      // audit 16 ago 2026): l'URL della richiesta contiene la API key in
      // query string (v. sopra), e alcune eccezioni HTTP (es.
      // ClientException di package:http) includono l'URL completo nel
      // proprio toString(). Quel messaggio risale fino a una snackbar
      // mostrata all'utente (receipt_scan_page.dart) — la key finirebbe
      // visibile a schermo.
      throw GeminiApiException('Impossibile contattare Gemini.');
    }

    if (response.statusCode == 400 || response.statusCode == 403) {
      throw GeminiApiException('API key Gemini non valida o non autorizzata.');
    }
    if (response.statusCode == 429) {
      throw GeminiApiException(
        'Limite giornaliero gratuito di Gemini superato, riprova più tardi.',
      );
    }
    if (response.statusCode != 200) {
      throw GeminiApiException(
        'Gemini HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw GeminiApiException(
        'Gemini non ha restituito alcun risultato (contenuto forse bloccato '
        'dai filtri di sicurezza).',
      );
    }

    final content = (candidates.first as Map<String, dynamic>)['content']
        as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    final rawModelOutput = parts == null || parts.isEmpty
        ? ''
        : (parts.first as Map<String, dynamic>)['text'] as String? ?? '';

    return _parseModelOutput(rawModelOutput);
  }

  AiReceiptResult _parseModelOutput(String raw) {
    var cleaned = raw.trim();
    // Con response_mime_type: "application/json" Gemini non dovrebbe
    // aggiungere fence markdown, ma restiamo tolleranti nel caso.
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(json)?'), '')
          .replaceFirst(RegExp(r'```$'), '')
          .trim();
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(cleaned) as Map<String, dynamic>;
    } on FormatException {
      throw GeminiApiException(
        'Risposta di Gemini non interpretabile come JSON: $raw',
      );
    }

    return AiReceiptResult(
      merchantName: _asNonEmptyString(json['negozio']),
      total: _asDouble(json['totale']),
      date: _asDate(json['data']),
    );
  }

  String? _asNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  DateTime? _asDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }
}
