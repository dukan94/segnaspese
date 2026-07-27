import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'subcategories_table.dart';

/// Esercenti/negozi riconosciuti (es. "Esselunga"), con categoria di
/// default proposta automaticamente quando si scansiona un loro scontrino.
class Merchants extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 120)();

  IntColumn get defaultCategoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get defaultSubCategoryId =>
      integer().nullable().references(SubCategories, #id)();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Id stabile tra dispositivi per il SyncService Turso (v. Transactions.syncId).
  /// NOTA: tabella non ancora collegata a un DAO/repository (in attesa del
  /// flusso OCR/merchant di M3-M6): colonna presente per coerenza di schema,
  /// ma non ancora inclusa nel motore di sync.
  /// Unicità imposta da un indice separato (app_database.dart, beforeOpen):
  /// SQLite non permette ALTER TABLE ADD COLUMN con vincolo UNIQUE inline.
  TextColumn get syncId => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}
