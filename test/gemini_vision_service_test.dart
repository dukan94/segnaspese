import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finance_app/data/services/gemini_vision_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Fake che sostituisce la sola chiamata HTTP vera ([GeminiVisionService.
/// sendRequest]) con una risposta/eccezione decisa dal test — stesso
/// principio di `FakeTursoHttpClient`: testa la logica di produzione reale
/// ([GeminiVisionService.analyzeReceipt]) senza fare mai una vera chiamata
/// di rete né mockare `package:http`.
class _FakeGeminiVisionService extends GeminiVisionService {
  _FakeGeminiVisionService(this._handler);

  final FutureOr<http.Response> Function(Uri uri, String jsonBody) _handler;

  Uri? lastUri;

  @override
  Future<http.Response> sendRequest(Uri uri, String jsonBody) async {
    lastUri = uri;
    return _handler(uri, jsonBody);
  }
}

http.Response _geminiEnvelope(String modelText, {int statusCode = 200}) {
  return http.Response(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': modelText},
            ],
          },
        },
      ],
    }),
    statusCode,
  );
}

void main() {
  late Directory tempDir;
  late File image;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gemini_vision_service_test');
    image = File('${tempDir.path}/receipt.jpg')..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<AiReceiptResult> analyze(_FakeGeminiVisionService service) {
    return service.analyzeReceipt(image, apiKey: 'segreta-123', model: 'gemini-test');
  }

  group('analyzeReceipt — parsing di una risposta valida', () {
    test('estrae negozio, importo e data da JSON pulito', () async {
      final service = _FakeGeminiVisionService((uri, body) => _geminiEnvelope(
            '{"negozio":"Esselunga","totale":42.8,"data":"2026-08-01"}',
          ));

      final result = await analyze(service);

      expect(result.merchantName, 'Esselunga');
      expect(result.total, 42.8);
      expect(result.date, DateTime.parse('2026-08-01'));
    });

    test('interpreta un importo con la virgola come separatore decimale',
        () async {
      final service = _FakeGeminiVisionService((uri, body) => _geminiEnvelope(
            '{"negozio":"Q8","totale":"60,50","data":null}',
          ));

      final result = await analyze(service);

      expect(result.total, 60.5);
      expect(result.date, isNull);
    });

    test('rimuove i fence markdown ```json ... ``` se presenti', () async {
      final service = _FakeGeminiVisionService((uri, body) => _geminiEnvelope(
            '```json\n{"negozio":"Amazon","totale":19.99,"data":null}\n```',
          ));

      final result = await analyze(service);

      expect(result.merchantName, 'Amazon');
      expect(result.total, 19.99);
    });

    test('un negozio vuoto o solo spazi diventa null', () async {
      final service = _FakeGeminiVisionService((uri, body) => _geminiEnvelope(
            '{"negozio":"   ","totale":null,"data":null}',
          ));

      final result = await analyze(service);

      expect(result.merchantName, isNull);
      expect(result.total, isNull);
    });
  });

  group('analyzeReceipt — errori HTTP', () {
    test('400 -> API key non valida', () async {
      final service = _FakeGeminiVisionService(
          (uri, body) => http.Response('{}', 400));
      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>().having(
            (e) => e.message, 'message', contains('non valida'))),
      );
    });

    test('403 -> API key non valida', () async {
      final service = _FakeGeminiVisionService(
          (uri, body) => http.Response('{}', 403));
      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>().having(
            (e) => e.message, 'message', contains('non valida'))),
      );
    });

    test('429 -> limite giornaliero superato', () async {
      final service = _FakeGeminiVisionService(
          (uri, body) => http.Response('{}', 429));
      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>()
            .having((e) => e.message, 'message', contains('Limite'))),
      );
    });

    test('altro status code -> messaggio con status e body', () async {
      final service = _FakeGeminiVisionService(
          (uri, body) => http.Response('errore interno', 500));
      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>().having(
            (e) => e.message, 'message', contains('500'))),
      );
    });

    test('candidates vuoto -> contenuto forse bloccato', () async {
      final service = _FakeGeminiVisionService(
          (uri, body) => http.Response(jsonEncode({'candidates': []}), 200));
      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>().having(
            (e) => e.message, 'message', contains('bloccato'))),
      );
    });

    test('testo del modello non interpretabile come JSON -> eccezione con il testo grezzo',
        () async {
      final service = _FakeGeminiVisionService(
          (uri, body) => _geminiEnvelope('non sono JSON'));
      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>().having((e) => e.message, 'message',
            contains('non sono JSON'))),
      );
    });
  });

  group('analyzeReceipt — sicurezza: la API key non deve mai comparire nel messaggio d\'errore (M18)', () {
    test('timeout -> messaggio fisso, nessuna key', () async {
      final service = _FakeGeminiVisionService((uri, body) async {
        throw TimeoutException('timed out');
      });

      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>()
            .having((e) => e.message, 'message', isNot(contains('segreta-123')))
            .having((e) => e.message, 'message', contains('30s'))),
      );
    });

    test('nessuna connessione (SocketException) -> messaggio fisso, nessuna key',
        () async {
      final service = _FakeGeminiVisionService((uri, body) async {
        throw const SocketException('Failed host lookup');
      });

      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>()
            .having((e) => e.message, 'message', isNot(contains('segreta-123')))
            .having((e) => e.message, 'message', contains('connessione'))),
      );
    });

    test(
        'un\'eccezione generica che include l\'URL (con la key) nel proprio '
        'toString() non deve mai farla trapelare nel messaggio', () async {
      final service = _FakeGeminiVisionService((uri, body) async {
        // Simula ClientException di package:http, che include l'URL
        // completo (con la key in query string) nel proprio toString().
        throw Exception('Connection failed, uri=$uri');
      });

      await expectLater(
        analyze(service),
        throwsA(isA<GeminiApiException>()
            .having((e) => e.message, 'message', isNot(contains('segreta-123')))
            .having((e) => e.message, 'message', isNot(contains('uri=')))),
      );
      // L'URL richiesto conteneva davvero la key (altrimenti il test non
      // proverebbe nulla): la garanzia è che non finisca nel messaggio.
      expect(service.lastUri.toString(), contains('segreta-123'));
    });
  });
}
