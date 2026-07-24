import 'package:drift/drift.dart';
import 'categories_table.dart';
import 'subcategories_table.dart';
import 'merchants_table.dart';
import 'recurring_table.dart';

/// Ogni entrata/uscita registrata dall'utente, manualmente o da scontrino.
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  DateTimeColumn get date => dateTime()();

  /// Sempre positivo: il segno è determinato da [type].
  RealColumn get amount => real()();

  IntColumn get type => intEnum<TransactionKind>()();

  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get subCategoryId =>
      integer().nullable().references(SubCategories, #id)();
  IntColumn get merchantId =>
      integer().nullable().references(Merchants, #id)();

  TextColumn get note => text().nullable()();

  /// Spesa/entrata "una tantum" (straordinaria): esclusa di default dalle
  /// statistiche/previsione della Dashboard, dove è attivabile con un toggle.
  BoolColumn get isExtraordinary =>
      boolean().withDefault(const Constant(false))();

  /// Rimborso ricevuto su una spesa: la operazione resta nella categoria di
  /// spesa ma viene sottratta dal suo totale (spesa netta), senza contare
  /// come entrata. Significativo solo per le uscite.
  BoolColumn get isRefund => boolean().withDefault(const Constant(false))();

  /// Path locale della foto dello scontrino, se inserito tramite scansione.
  TextColumn get receiptImagePath => text().nullable()();

  /// Valorizzato se la transazione è stata generata automaticamente da una
  /// ricorrenza (es. Netflix mensile).
  IntColumn get recurringId =>
      integer().nullable().references(RecurringTransactions, #id)();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
