import 'package:drift/drift.dart';
import 'categories_table.dart';

enum BudgetPeriod { monthly, yearly }

/// Budget impostato dall'utente, globale (categoryId nullo) o per singola
/// categoria, mensile o annuale.
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// null = budget complessivo (non legato a una categoria specifica).
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();

  IntColumn get period => intEnum<BudgetPeriod>()();
  RealColumn get amount => real()();

  /// Permette di storicizzare cambi di budget nel tempo.
  DateTimeColumn get startDate => dateTime()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Id stabile tra dispositivi per il SyncService Turso (v. Transactions.syncId).
  /// Unicità imposta da un indice separato (app_database.dart, beforeOpen):
  /// SQLite non permette ALTER TABLE ADD COLUMN con vincolo UNIQUE inline.
  TextColumn get syncId => text().nullable()();
}
