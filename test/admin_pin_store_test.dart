import 'package:finance_app/data/services/admin_pin_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `AdminPinStore` (M48): stesso principio dei test già esistenti su
/// `SafeTransactionDeletionService`/`TursoSyncService` — test double
/// ufficiale del pacchetto (`TestFlutterSecureStoragePlatform`), niente
/// binding Flutter/platform channel reale necessario.
void main() {
  late AdminPinStore store;

  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
    store = AdminPinStore(secureStorage: const FlutterSecureStorage());
  });

  group('AdminPinStore', () {
    test('isSet false quando nessun PIN è mai stato impostato', () async {
      expect(await store.isSet(), isFalse);
    });

    test('dopo setPin, isSet torna true', () async {
      await store.setPin('1234');
      expect(await store.isSet(), isTrue);
    });

    test('verify torna true con il PIN corretto', () async {
      await store.setPin('1234');
      expect(await store.verify('1234'), isTrue);
    });

    test('verify torna false con un PIN sbagliato', () async {
      await store.setPin('1234');
      expect(await store.verify('9999'), isFalse);
    });

    test('verify torna false se nessun PIN è mai stato impostato', () async {
      expect(await store.verify('1234'), isFalse);
    });

    test('il PIN non è mai salvato in chiaro, solo il suo hash', () async {
      await store.setPin('1234');
      final raw =
          await const FlutterSecureStorage().read(key: 'admin_pin_hash');
      expect(raw, isNotNull);
      expect(raw, isNot('1234'));
    });

    test('clear rimuove il PIN: isSet torna false, verify sempre false',
        () async {
      await store.setPin('1234');
      await store.clear();
      expect(await store.isSet(), isFalse);
      expect(await store.verify('1234'), isFalse);
    });

    test('cambiare PIN sovrascrive il precedente: il vecchio non funziona più',
        () async {
      await store.setPin('1234');
      await store.setPin('5678');
      expect(await store.verify('1234'), isFalse);
      expect(await store.verify('5678'), isTrue);
    });
  });
}
