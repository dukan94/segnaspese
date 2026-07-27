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
