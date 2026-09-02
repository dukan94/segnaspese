import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage sicuro del PIN che protegge il pannello Admin (M48) — stesso
/// pattern già usato per le altre credenziali (`gemini_api_key_store.dart`,
/// Turso), ma qui non salviamo mai il PIN in chiaro: solo il suo hash
/// SHA-256, che basta per verificarlo senza doverlo poter rileggere.
/// Locale al dispositivo, mai sincronizzato: protegge "non far pasticciare
/// chi ha in mano questo telefono", non un canale verso il database di un
/// altro utente (quello è già impossibile — ognuno punta al proprio Turso).
class AdminPinStore {
  AdminPinStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _key = 'admin_pin_hash';

  String _hash(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<bool> isSet() async {
    final value = await _secureStorage.read(key: _key);
    return value != null && value.isNotEmpty;
  }

  Future<void> setPin(String pin) =>
      _secureStorage.write(key: _key, value: _hash(pin));

  Future<bool> verify(String pin) async {
    final stored = await _secureStorage.read(key: _key);
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  Future<void> clear() => _secureStorage.delete(key: _key);
}
