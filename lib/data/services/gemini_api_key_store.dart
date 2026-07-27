import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage sicuro della API key Gemini (Google AI Studio), stesso pattern
/// già usato per le credenziali Turso in `turso_sync_service.dart`.
class GeminiApiKeyStore {
  GeminiApiKeyStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _key = 'gemini_api_key';

  Future<String?> read() => _secureStorage.read(key: _key);

  Future<void> write(String apiKey) =>
      _secureStorage.write(key: _key, value: apiKey);

  Future<bool> isConfigured() async {
    final value = await read();
    return value != null && value.isNotEmpty;
  }
}
