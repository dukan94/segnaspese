import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage sicuro della chiave JSON del service account Google, stesso
/// pattern già usato per Gemini/Turso (v. gemini_api_key_store.dart).
class GoogleSheetsCredentialsStore {
  GoogleSheetsCredentialsStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _key = 'google_sheets_service_account_json';

  Future<String?> read() => _secureStorage.read(key: _key);

  Future<void> write(String json) =>
      _secureStorage.write(key: _key, value: json);

  Future<bool> isConfigured() async {
    final value = await read();
    return value != null && value.isNotEmpty;
  }
}
