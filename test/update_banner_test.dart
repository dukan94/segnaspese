import 'package:finance_app/core/di/update_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `shouldShowUpdateBanner` (M47): logica pura di quando mostrare
/// l'avviso "nuova versione disponibile" in Home, estratta apposta per
/// essere testabile senza Riverpod/rete.
void main() {
  group('shouldShowUpdateBanner', () {
    test('build locale/di sviluppo (currentBuildNumber 0): sempre false, '
        'anche con una build remota disponibile', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 0,
          latestBuildNumber: 42,
          dismissedBuildNumber: null,
        ),
        isFalse,
      );
    });

    test('nessuna build remota determinabile: false', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 40,
          latestBuildNumber: null,
          dismissedBuildNumber: null,
        ),
        isFalse,
      );
    });

    test('build remota uguale a quella in esecuzione: false', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 40,
          latestBuildNumber: 40,
          dismissedBuildNumber: null,
        ),
        isFalse,
      );
    });

    test('build remota più vecchia di quella in esecuzione: false', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 40,
          latestBuildNumber: 39,
          dismissedBuildNumber: null,
        ),
        isFalse,
      );
    });

    test('build remota più recente, mai chiuso: true', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 40,
          latestBuildNumber: 41,
          dismissedBuildNumber: null,
        ),
        isTrue,
      );
    });

    test('chiuso per questa specifica build remota: false', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 40,
          latestBuildNumber: 41,
          dismissedBuildNumber: '41',
        ),
        isFalse,
      );
    });

    test('chiuso per una build precedente, ne è uscita una ancora più '
        'recente: riappare, true', () {
      expect(
        shouldShowUpdateBanner(
          currentBuildNumber: 40,
          latestBuildNumber: 42,
          dismissedBuildNumber: '41',
        ),
        isTrue,
      );
    });
  });
}
