import 'package:drift/drift.dart';

/// Impostazioni semplici key-value (es. "themeMode" -> "dark",
/// "currency" -> "EUR").
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
