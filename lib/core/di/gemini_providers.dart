import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/services/gemini_api_key_store.dart';
import '../../data/services/gemini_vision_service.dart';
import 'database_provider.dart';

const geminiModelSettingsKey = 'gemini_model';
const geminiModelDefault = 'gemini-2.5-flash';

final geminiApiKeyStoreProvider = Provider<GeminiApiKeyStore>((ref) {
  return GeminiApiKeyStore();
});

final geminiVisionServiceProvider = Provider<GeminiVisionService>((ref) {
  return const GeminiVisionService();
});

/// Nome del modello Gemini da usare per l'analisi (es. "gemini-2.5-flash").
/// Non è un segreto (a differenza della API key, in `flutter_secure_storage`
/// via `geminiApiKeyStoreProvider`): stesso pattern key-value su tabella
/// `Settings` già usato per `annualSavingsGoalProvider`.
final geminiModelProvider = StreamProvider<String>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)
        ..where((s) => s.key.equals(geminiModelSettingsKey)))
      .watchSingleOrNull()
      .map((row) => row?.value ?? geminiModelDefault);
});

final setGeminiModelProvider = Provider<Future<void> Function(String)>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return (String value) => db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: geminiModelSettingsKey,
            value: value,
            updatedAt: Value(DateTime.now()),
          ),
        );
  },
);
