import 'package:drift/drift.dart';
import 'categories_table.dart';

/// Sottocategorie (es. "Spesa" sotto "Casa", "Carburante" sotto "Auto").
class SubCategories extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get categoryId =>
      integer().references(Categories, #id)();

  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get icon => text().withDefault(const Constant(''))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
