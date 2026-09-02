import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/local/seed/onboarding_check.dart' show onboardingCompletedSettingsKey;
import 'database_provider.dart';

/// Schermata del wizard su cui riprendere se l'utente esce dall'app (o il
/// processo viene ucciso, es. passando al browser per creare il database
/// Turso) e poi rientra prima di aver completato l'onboarding. Valori:
/// 'welcome' (default se assente) | 'turso' | 'done'.
const String onboardingStepSettingsKey = 'onboarding_step';
const String onboardingStepWelcome = 'welcome';
const String onboardingStepTurso = 'turso';
const String onboardingStepDone = 'done';

final onboardingStepProvider = StreamProvider<String>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)
        ..where((s) => s.key.equals(onboardingStepSettingsKey)))
      .watchSingleOrNull()
      .map((row) => row?.value ?? onboardingStepWelcome);
});

final setOnboardingStepProvider = Provider<Future<void> Function(String)>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return (String step) => db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: onboardingStepSettingsKey,
            value: step,
            updatedAt: Value(DateTime.now()),
          ),
        );
  },
);

/// Marca l'onboarding come completato (fine wizard, "Salta per ora"
/// incluso — saltare è comunque una scelta consapevole, non va richiesta
/// di nuovo al prossimo avvio).
final completeOnboardingProvider = Provider<Future<void> Function()>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return () => db.into(db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: onboardingCompletedSettingsKey,
          value: 'true',
          updatedAt: Value(DateTime.now()),
        ),
      );
});
