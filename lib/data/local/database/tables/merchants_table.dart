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

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}
