import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import 'database_provider.dart';

/// Chiave dell'obiettivo di risparmio annuo nella tabella Settings.
const String _savingsGoalKey = 'annual_savings_goal';

/// Obiettivo di risparmio annuo impostato dall'utente (null se non impostato).
final annualSavingsGoalProvider = StreamProvider<double?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.settings)..where((s) => s.key.equals(_savingsGoalKey)))
      .watchSingleOrNull()
      .map((row) => row == null ? null : double.tryParse(row.value));
});

/// Setter dell'obiettivo di risparmio annuo.
final setAnnualSavingsGoalProvider = Provider<Future<void> Function(double)>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return (double value) => db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _savingsGoalKey,
            value: value.toString(),
          ),
        );
  },
);
