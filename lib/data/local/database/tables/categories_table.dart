import 'package:drift/drift.dart';

/// Tipi di movimento supportati dall'app.
enum TransactionKind { income, expense }

/// Tabella delle categorie principali (es. Casa, Auto, Stipendio...).
///
/// Completamente personalizzabile dall'utente: [isDefault] serve solo per
/// evitare che le categorie create al primo avvio vengano cancellate per
/// errore, ma l'utente può comunque modificarle o disattivarle.
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// Emoji o codice icona (es. "🏠").
  TextColumn get icon => text()();

  /// income / expense
  IntColumn get type => intEnum<TransactionKind>()();

  /// Colore ARGB usato nei grafici della dashboard.
  IntColumn get color => integer()();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  // --- Campi di sync (v. progettazione, sezione "Sync multi-dispositivo") ---
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}
