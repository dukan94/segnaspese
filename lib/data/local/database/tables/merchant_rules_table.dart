import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'subcategories_table.dart';

/// Regole di classificazione automatica scontrini, completamente
/// modificabili dall'utente (mai hardcoded nel codice).
///
/// Esempio: pattern "ESSEL.*" -> Categoria "Casa" / Sottocategoria "Spesa".
class MerchantRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Espressione regolare applicata al testo estratto dall'OCR
  /// (es. "ESSEL.*", case-insensitive).
  TextColumn get pattern => text()();

  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get subCategoryId =>
      integer().nullable().references(SubCategories, #id)();

  /// Priorità di match in caso di più regole compatibili (più alto = prima).
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// true se creata automaticamente dal flusso di apprendimento
  /// (negozio sconosciuto -> l'utente sceglie la categoria una volta).
  BoolColumn get isUserDefined =>
      boolean().withDefault(const Constant(true))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Id stabile tra dispositivi per il SyncService Turso (v. Transactions.syncId).
  /// Unicità imposta da un indice separato (app_database.dart, beforeOpen):
  /// SQLite non permette ALTER TABLE ADD COLUMN con vincolo UNIQUE inline.
  TextColumn get syncId => text().nullable()();
}
