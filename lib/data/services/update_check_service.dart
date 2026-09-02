import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Estrae il numero di build per la piattaforma da un `version.json` già
/// decodificato — funzione pura, separata dalla chiamata di rete apposta
/// per essere testabile senza dipendere dalla piattaforma reale su cui
/// gira il test (`Platform.isAndroid` sarebbe sempre `false` in
/// `flutter test`, eseguito sull'host, non su un dispositivo Android).
int? extractBuildNumberForPlatform(
  Map<String, dynamic> json, {
  required bool isAndroid,
}) {
  final value = json[isAndroid ? 'android' : 'windows'];
  return value is int ? value : null;
}

/// Legge da un piccolo `version.json` pubblico (GitHub Pages, M47) il
/// numero di build più recente pubblicato per Android/Windows — v.
/// CLAUDE.md "Distribuzione" per il perché GitHub Pages (repo privato, mai
/// un token incorporato nell'app per leggerlo). Aggiornato dai workflow
/// `android-build.yml`/`windows-build.yml` dopo ogni pubblicazione riuscita
/// sulla rispettiva release fissa (M46).
class UpdateCheckService {
  const UpdateCheckService();

  static final Uri _versionUrl =
      Uri.parse('https://dukan94.github.io/segnaspese/version.json');

  /// Isolata in un metodo proprio per poterla sostituire nei test — stesso
  /// principio già in uso per `GeminiVisionService.sendRequest`/
  /// `TursoHttpClient.execute`. Timeout breve (10s, più corto dei 30s di
  /// Turso/Gemini): un file statico pubblico che non risponde in fretta
  /// non deve far percepire un ritardo all'apertura della Home.
  Future<http.Response> sendRequest(Uri uri) {
    return http.get(uri).timeout(const Duration(seconds: 10));
  }

  /// Numero di build più recente per la piattaforma corrente, o `null` se
  /// non determinabile (rete assente, GitHub Pages non ancora attivato/
  /// propagato, JSON non valido). Non lancia mai un'eccezione: un
  /// controllo di aggiornamento fallito non deve mai disturbare l'uso
  /// dell'app — nessun banner, nessun errore mostrato (stesso principio di
  /// isolamento errori non critici già seguito per sync/Google Sheets).
  Future<int?> fetchLatestBuildNumber() async {
    try {
      final response = await sendRequest(_versionUrl);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return extractBuildNumberForPlatform(decoded, isAndroid: Platform.isAndroid);
    } catch (_) {
      return null;
    }
  }
}
