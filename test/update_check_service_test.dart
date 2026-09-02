import 'package:finance_app/data/services/update_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `extractBuildNumberForPlatform` (M47): logica pura di lettura
/// del version.json già decodificato, separata dalla chiamata di rete
/// apposta per essere testabile senza dipendere da `Platform.isAndroid`
/// (sempre `false` in `flutter test`, eseguito sull'host).
void main() {
  group('extractBuildNumberForPlatform', () {
    test('Android: legge la chiave "android"', () {
      expect(
        extractBuildNumberForPlatform(
          {'android': 12, 'windows': 7},
          isAndroid: true,
        ),
        12,
      );
    });

    test('Windows: legge la chiave "windows"', () {
      expect(
        extractBuildNumberForPlatform(
          {'android': 12, 'windows': 7},
          isAndroid: false,
        ),
        7,
      );
    });

    test('chiave mancante per la piattaforma richiesta: null', () {
      expect(
        extractBuildNumberForPlatform({'android': 12}, isAndroid: false),
        isNull,
      );
    });

    test('valore non intero (es. stringa): null, non un cast a caso', () {
      expect(
        extractBuildNumberForPlatform({'windows': '7'}, isAndroid: false),
        isNull,
      );
    });

    test('JSON vuoto: null per entrambe le piattaforme', () {
      expect(extractBuildNumberForPlatform({}, isAndroid: true), isNull);
      expect(extractBuildNumberForPlatform({}, isAndroid: false), isNull);
    });
  });
}
