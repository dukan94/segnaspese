import 'package:drift/drift.dart';

/// Impostazioni semplici key-value (es. "themeMode" -> "dark",
/// "currency" -> "EUR").
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  /// Usato dal SyncService (M7) per le chiavi sincronizzate (v.
  /// savingsGoalSettingsKey in settings_providers.dart) e per le proprie
  /// filigrane interne di sync; per le altre chiavi (ordine categorie,
  /// ecc.) non è consultato da nessuno.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}
