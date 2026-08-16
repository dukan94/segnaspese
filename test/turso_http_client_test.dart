import 'dart:async';
import 'dart:convert';

import 'package:finance_app/data/services/turso_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Fake che sostituisce la sola chiamata HTTP vera ([TursoHttpClient.
/// sendRequest]) con una risposta/eccezione decisa dal test. A differenza
/// di `FakeTursoHttpClient` (test/fakes/, sovrascrive `execute` per intero
/// per simulare un DB remoto in-memory), questo esercita `execute()` reale
/// — quindi anche `_encodeArg`/`_decodeCell`/la costruzione del payload
/// Hrana — senza fare mai una vera chiamata di rete.
class _FakeTransport extends TursoHttpClient {
  _FakeTransport(this._handler, {super.baseUrl = 'libsql://test.turso.io/', super.authToken = 'test-token'});

  final FutureOr<http.Response> Function(Uri uri, String body) _handler;

  Uri? lastUri;
  String? lastBody;

  @override
  Future<http.Response> sendRequest(Uri uri, String body) async {
    lastUri = uri;
    lastBody = body;
    return _handler(uri, body);
  }
}

http.Response _pipelineResponse(List<Map<String, dynamic>> results) {
  return http.Response(jsonEncode({'results': results}), 200);
}

Map<String, dynamic> _okResult(List<String> cols, List<List<Map<String, Object?>>> rows) {
  return {
    'type': 'ok',
    'response': {
      'result': {
        'cols': [for (final c in cols) {'name': c}],
        'rows': rows,
      },
    },
  };
}

void main() {
  group('_normalizeBaseUrl (via costruzione + URL richiesto)', () {
    test('converte "libsql://" in "https://" e toglie lo slash finale',
        () async {
      final client = _FakeTransport(
        (uri, body) => _pipelineResponse([_okResult(['x'], [])]),
        baseUrl: 'libsql://esempio.turso.io/',
        authToken: 't',
      );

      await client.execute([const TursoStatement('SELECT 1')]);

      expect(client.lastUri.toString(), 'https://esempio.turso.io/v2/pipeline');
    });

    test('un URL già https:// senza slash finale resta invariato', () async {
      final client = _FakeTransport(
        (uri, body) => _pipelineResponse([_okResult(['x'], [])]),
        baseUrl: 'https://esempio.turso.io',
        authToken: 't',
      );

      await client.execute([const TursoStatement('SELECT 1')]);

      expect(client.lastUri.toString(), 'https://esempio.turso.io/v2/pipeline');
    });
  });

  group('execute — costruzione della richiesta (_encodeArg)', () {
    test('lista vuota di statement non chiama nemmeno la rete', () async {
      var called = false;
      final client = _FakeTransport((uri, body) {
        called = true;
        return _pipelineResponse([]);
      });

      final result = await client.execute(const []);

      expect(result, isEmpty);
      expect(called, isFalse);
    });

    test('codifica int, double, bool, null e String secondo il protocollo Hrana',
        () async {
      final client = _FakeTransport((uri, body) => _pipelineResponse([
            _okResult(['x'], []),
          ]));

      await client.execute([
        const TursoStatement(
          'INSERT INTO t VALUES (?, ?, ?, ?, ?)',
          [42, 3.14, true, null, 'ciao'],
        ),
      ]);

      final decodedBody = jsonDecode(client.lastBody!) as Map<String, dynamic>;
      final args = (decodedBody['requests'] as List)[0]['stmt']['args'] as List;

      expect(args[0], {'type': 'integer', 'value': '42'});
      expect(args[1], {'type': 'float', 'value': 3.14});
      expect(args[2], {'type': 'integer', 'value': '1'}); // bool true -> "1"
      expect(args[3], {'type': 'null'});
      expect(args[4], {'type': 'text', 'value': 'ciao'});
    });

    test('ogni richiesta batch termina con uno statement "close"', () async {
      final client = _FakeTransport(
          (uri, body) => _pipelineResponse([_okResult(['x'], [])]));

      await client.execute([const TursoStatement('SELECT 1')]);

      final decodedBody = jsonDecode(client.lastBody!) as Map<String, dynamic>;
      final requests = decodedBody['requests'] as List;
      expect(requests.last, {'type': 'close'});
    });
  });

  group('execute — decodifica della risposta (_decodeCell)', () {
    test('decodifica ogni tipo di cella (null/integer/float/text/blob)',
        () async {
      final client = _FakeTransport((uri, body) => _pipelineResponse([
            _okResult(
              ['a', 'b', 'c', 'd', 'e'],
              [
                [
                  {'type': 'null'},
                  {'type': 'integer', 'value': '9223372036854775807'},
                  {'type': 'float', 'value': 1.5},
                  {'type': 'text', 'value': 'ciao'},
                  {'type': 'blob', 'base64': 'aGVsbG8='},
                ],
              ],
            ),
          ]));

      final results = await client.execute([const TursoStatement('SELECT *')]);

      expect(results, hasLength(1));
      expect(results.single.columns, ['a', 'b', 'c', 'd', 'e']);
      final row = results.single.rows.single;
      expect(row[0], isNull);
      expect(row[1], 9223372036854775807); // precisione a 64 bit preservata
      expect(row[2], 1.5);
      expect(row[3], 'ciao');
      expect(row[4], 'aGVsbG8=');
    });

    test('asMaps() converte righe posizionali in mappa colonna->valore',
        () async {
      final client = _FakeTransport((uri, body) => _pipelineResponse([
            _okResult(['nome', 'eta'], [
              [
                {'type': 'text', 'value': 'Mario'},
                {'type': 'integer', 'value': '40'},
              ],
            ]),
          ]));

      final results = await client.execute([const TursoStatement('SELECT *')]);

      expect(results.single.asMaps(), [
        {'nome': 'Mario', 'eta': 40},
      ]);
    });

    test('più statement nello stesso batch restituiscono un risultato ciascuno, nello stesso ordine',
        () async {
      final client = _FakeTransport((uri, body) => _pipelineResponse([
            _okResult(['a'], [
              [
                {'type': 'integer', 'value': '1'}
              ]
            ]),
            _okResult(['b'], [
              [
                {'type': 'integer', 'value': '2'}
              ]
            ]),
          ]));

      final results = await client.execute([
        const TursoStatement('SELECT 1'),
        const TursoStatement('SELECT 2'),
      ]);

      expect(results, hasLength(2));
      expect(results[0].rows.single.single, 1);
      expect(results[1].rows.single.single, 2);
    });
  });

  group('execute — gestione errori', () {
    test('uno statement con type "error" lancia TursoApiException', () async {
      final client = _FakeTransport((uri, body) => _pipelineResponse([
            {'type': 'error', 'error': 'no such table: foo'},
          ]));

      await expectLater(
        client.execute([const TursoStatement('SELECT * FROM foo')]),
        throwsA(isA<TursoApiException>().having(
            (e) => e.message, 'message', contains('no such table'))),
      );
    });

    test('status HTTP diverso da 200 lancia TursoApiException con status e body',
        () async {
      final client =
          _FakeTransport((uri, body) => http.Response('unauthorized', 401));

      await expectLater(
        client.execute([const TursoStatement('SELECT 1')]),
        throwsA(isA<TursoApiException>()
            .having((e) => e.message, 'message', contains('401'))),
      );
    });

    test('timeout -> messaggio dedicato', () async {
      final client = _FakeTransport((uri, body) async {
        throw TimeoutException('timed out');
      });

      await expectLater(
        client.execute([const TursoStatement('SELECT 1')]),
        throwsA(isA<TursoApiException>()
            .having((e) => e.message, 'message', contains('30s'))),
      );
    });

    test('altra eccezione di rete -> messaggio con l\'eccezione originale (il token è in header, non in URL: nessun rischio di leak, a differenza di Gemini/M18)',
        () async {
      final client = _FakeTransport((uri, body) async {
        throw Exception('connection reset');
      });

      await expectLater(
        client.execute([const TursoStatement('SELECT 1')]),
        throwsA(isA<TursoApiException>().having(
            (e) => e.message, 'message', contains('connection reset'))),
      );
    });
  });
}
