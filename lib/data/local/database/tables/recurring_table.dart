import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'subcategories_table.dart';

enum RecurringFrequency { weekly, monthly, yearly }

/// Movimenti ricorrenti (es. "Netflix 12,99€ ogni mese",
/// "Stipendio 1.800€ ogni mese"). Generano automaticamente le Transactions
/// corrispondenti quando è dovuta la prossima occorrenza.
class RecurringTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get description => text()();
  RealColumn get amount => real()();
  IntColumn get type => intEnum<TransactionKind>()();

  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get subCategoryId =>
      integer().nullable().references(SubCategories, #id)();

  IntColumn get frequency => intEnum<RecurringFrequency>()();

  /// Giorno del mese in cui generare la transazione (per frequency=monthly).
  IntColumn get dayOfMonth => integer().nullable()();

  DateTimeColumn get nextOccurrence => dateTime()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Numero totale di occorrenze da generare, poi la ricorrenza si mette in
  /// pausa da sola (v. RecurringDao.generateDue). Null = a tempo
  /// indeterminato (comportamento originale, invariato).
  IntColumn get totalOccurrences => integer().nullable()();

  /// Quante occorrenze sono già state generate finora (indipendente da
  /// eventuali transazioni generate poi eliminate dall'utente).
  IntColumn get occurrencesGenerated =>
      integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Id stabile tra dispositivi per il SyncService Turso (v. Transactions.syncId).
  /// Unicità imposta da un indice separato (app_database.dart, beforeOpen):
  /// SQLite non permette ALTER TABLE ADD COLUMN con vincolo UNIQUE inline.
  TextColumn get syncId => text().nullable()();
}
