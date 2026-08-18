import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/services/sync_service.dart' show savingsGoalSettingsKey;
import 'database_provider.dart';

/// Obiettivo di risparmio annuo impostato dall'utente (null se non impostato).
final annualSavingsGoalProvider = StreamProvider<double?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals(savingsGoalSettingsKey)))
      .watchSingleOrNull()
      .map((row) => row == null ? null : double.tryParse(row.value));
});

/// Setter dell'obiettivo di risparmio annuo.
final setAnnualSavingsGoalProvider = Provider<Future<void> Function(double)>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return (double value) => db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: savingsGoalSettingsKey,
            value: value.toString(),
            updatedAt: Value(DateTime.now()),
          ),
        );
  },
);

/// Mese (formato "YYYY-MM") in cui l'utente ha chiuso l'avviso di soglia
/// budget in Home (M40) — stato locale del banner, non un dato reale: non
/// va aggiunto alla whitelist di chiavi sincronizzate in
/// `turso_sync_service.dart` (stesso principio dell'ordine manuale
/// categorie, mai sincronizzato). Riappare da solo al mese successivo.
const String budgetAlertDismissedMonthSettingsKey =
    'budget_alert_dismissed_month';

final budgetAlertDismissedMonthProvider = StreamProvider<String?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)
        ..where((s) => s.key.equals(budgetAlertDismissedMonthSettingsKey)))
      .watchSingleOrNull()
      .map((row) => row?.value);
});

/// Setter: chiude l'avviso soglia budget per il mese indicato (formato
/// "YYYY-MM").
final dismissBudgetAlertProvider = Provider<Future<void> Function(String)>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return (String month) => db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: budgetAlertDismissedMonthSettingsKey,
            value: month,
            updatedAt: Value(DateTime.now()),
          ),
        );
  },
);
