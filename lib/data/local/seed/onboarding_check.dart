import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Segna che il wizard di primo avvio (M49, `presentation/onboarding/`) è
/// stato completato — a mano (fine wizard, incluso "Salta per ora") o in
/// automatico da [resolveNeedsOnboarding] per un dispositivo già in uso.
/// Dichiarata qui (non in `core/di/onboarding_providers.dart`) perché
/// [resolveNeedsOnboarding] gira in `main.dart` prima che l'albero dei
/// provider Riverpod serva a qualcosa — stesso principio già in uso per
/// `savingsGoalSettingsKey` in `sync_service.dart`.
const String onboardingCompletedSettingsKey = 'onboarding_completed';

/// Determina se il wizard di primo avvio va mostrato. Mai per un
/// dispositivo/installazione già in uso: se esiste già almeno una
/// transazione o la sync Turso risulta già configurata, l'onboarding viene
/// marcato completato in silenzio (backfill una tantum, stesso principio
/// della versione seed `kSeedVersion`) — nessun utente esistente vedrà mai
/// comparire il wizard dopo un aggiornamento dell'app. Il controllo pesante
/// (transazioni/Turso) gira una sola volta: una volta marcato completato,
/// le run successive si fermano al primo controllo (riga già presente).
Future<bool> resolveNeedsOnboarding(
  AppDatabase db, {
  required Future<bool> Function() isTursoConfigured,
}) async {
  final completedRow = await (db.select(db.settings)
        ..where((s) => s.key.equals(onboardingCompletedSettingsKey)))
      .getSingleOrNull();
  if (completedRow != null) return false;

  final hasTransactions =
      (await (db.select(db.transactions)..limit(1)).get()).isNotEmpty;
  final tursoConfigured = await isTursoConfigured();
  if (hasTransactions || tursoConfigured) {
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: onboardingCompletedSettingsKey,
            value: 'true',
            updatedAt: Value(DateTime.now()),
          ),
        );
    return false;
  }
  return true;
}
