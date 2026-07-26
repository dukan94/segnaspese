import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/categories_table.dart';
import 'tables/subcategories_table.dart';
import 'tables/merchants_table.dart';
import 'tables/merchant_rules_table.dart';
import 'tables/transactions_table.dart';
import 'tables/budgets_table.dart';
import 'tables/recurring_table.dart';
import 'tables/settings_table.dart';
import 'daos/transaction_dao.dart';
import 'daos/category_dao.dart';
import 'daos/budget_dao.dart';
import 'daos/merchant_rule_dao.dart';
import 'daos/recurring_dao.dart';

part 'app_database.g.dart';

/// Database locale dell'app, basato su SQLite tramite Drift.
///
/// Questo stesso file viene usato come "embedded replica" per la sync
/// multi-dispositivo su Turso (v. data/services/sync_service.dart):
/// l'app legge/scrive sempre in locale con latenza zero, la sync verso il
/// database remoto Turso avviene in background quando c'è connessione.
@DriftDatabase(
  tables: [
    Categories,
    SubCategories,
    Merchants,
    MerchantRules,
    Transactions,
    Budgets,
    RecurringTransactions,
    Settings,
  ],
  daos: [
    TransactionDao,
    CategoryDao,
    BudgetDao,
    MerchantRuleDao,
    RecurringDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Costruttore usato nei test, per iniettare un executor in-memory.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v2: colonna "isExtraordinary" sulle transazioni (spese/entrate
          // straordinarie). addColumn preserva i dati esistenti; le righe già
          // presenti prendono il default (false).
          if (from < 2) {
            await m.addColumn(transactions, transactions.isExtraordinary);
          }
          // v3: colonna "isRefund" (rimborso ricevuto su una spesa).
          if (from < 3) {
            await m.addColumn(transactions, transactions.isRefund);
          }
          // v4: colonna "refundOfId" (collegamento rimborso → spesa originale).
          if (from < 4) {
            await m.addColumn(transactions, transactions.refundOfId);
          }
        },
        // NOTA: l'ordine manuale (drag & drop) di categorie/sottocategorie
        // (v. CategoryDao) è salvato nella tabella Settings già esistente,
        // come elenco di id separati da virgola — nessuna nuova colonna né
        // migrazione di schema necessarie per quella funzionalità.
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Deliberatamente "application support" e non "documents": su Windows
    // la cartella Documenti è spesso reindirizzata su OneDrive (Known
    // Folder Move aziendale), che sincronizza in background il file
    // SQLite live causando blocchi/corruzioni — lo stesso tipo di problema
    // avuto con .dart_tool durante lo sviluppo. La cartella "support" non
    // è soggetta a questo reindirizzamento.
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'finance_app.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
