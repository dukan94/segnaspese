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

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
