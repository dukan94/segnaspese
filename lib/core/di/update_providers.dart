import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/services/update_check_service.dart';
import 'database_provider.dart';

/// Numero di build della build in esecuzione, passato dai workflow CI
/// (`android-build.yml`/`windows-build.yml`, M47) con
/// `--dart-define=BUILD_NUMBER=<github.run_number>` — un numero monotono e
/// automatico (mai deciso a mano), non un numero di versione semantico
/// (`pubspec.yaml` resta fermo a 0.1.0 da sempre, non affidabile per un
/// confronto). `0` per una build locale/di sviluppo, mai lanciata da CI:
/// non confrontabile con un numero di build reale, v.
/// [shouldShowUpdateBanner].
const int currentBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

final updateCheckServiceProvider = Provider<UpdateCheckService>((ref) {
  return const UpdateCheckService();
});

/// Numero di build più recente pubblicato per questa piattaforma (v.
/// `version.json` su GitHub Pages), o `null` se non determinabile. Un solo
/// controllo per sessione app (nessun refresh periodico): coerente con la
/// natura non urgente dell'avviso, stesso principio "solo l'essenziale"
/// già seguito per l'avviso soglia budget (M40).
final latestBuildNumberProvider = FutureProvider<int?>((ref) {
  return ref.watch(updateCheckServiceProvider).fetchLatestBuildNumber();
});

/// Numero di build per cui l'utente ha già chiuso il banner "nuova
/// versione disponibile" in Home — stato locale del banner, non un dato
/// reale: non va aggiunto alla whitelist di chiavi sincronizzate in
/// `turso_sync_service.dart` (stesso principio di
/// `budgetAlertDismissedMonthSettingsKey`). A differenza di quella chiave
/// (dismiss per mese), qui il dismiss è per numero di build: se esce una
/// build ancora più recente di quella chiusa, il banner riappare da solo.
const String updateBannerDismissedBuildSettingsKey =
    'update_banner_dismissed_build';

final updateBannerDismissedBuildProvider = StreamProvider<String?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)
        ..where((s) => s.key.equals(updateBannerDismissedBuildSettingsKey)))
      .watchSingleOrNull()
      .map((row) => row?.value);
});

/// Setter: chiude il banner per lo specifico numero di build indicato.
final dismissUpdateBannerProvider = Provider<Future<void> Function(String)>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return (String buildNumber) => db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: updateBannerDismissedBuildSettingsKey,
            value: buildNumber,
            updatedAt: Value(DateTime.now()),
          ),
        );
  },
);

/// Vero se va mostrato il banner "nuova versione disponibile" in Home
/// (M47): mai per una build locale/di sviluppo ([currentBuildNumber] 0),
/// mai se non è determinabile una build più recente pubblicata, mai se
/// non è effettivamente più recente di quella in esecuzione, mai se
/// l'utente l'ha già chiusa per QUESTA specifica build.
bool shouldShowUpdateBanner({
  required int currentBuildNumber,
  required int? latestBuildNumber,
  required String? dismissedBuildNumber,
}) {
  if (currentBuildNumber <= 0) return false;
  if (latestBuildNumber == null) return false;
  if (latestBuildNumber <= currentBuildNumber) return false;
  return dismissedBuildNumber != latestBuildNumber.toString();
}

/// Link fisso della release (M37/M46) da aprire per scaricare
/// l'aggiornamento, per la piattaforma corrente.
String updateDownloadUrl() {
  return Platform.isAndroid
      ? 'https://github.com/dukan94/segnaspese/releases/download/android-latest/Tally-Android.apk'
      : 'https://github.com/dukan94/segnaspese/releases/download/windows-latest/Tally-Windows.zip';
}
