import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
  int get schemaVersion => 5;

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
          // v5: colonna "syncId" su tutte le tabelle sincronizzabili
          // (Milestone M7). addColumn la crea nulla per le righe esistenti,
          // poi la backfilliamo con un UUID v4 generato per riga: il
          // SyncService la richiede sempre valorizzata per identificare le
          // righe tra dispositivi diversi.
          if (from < 5) {
            await m.addColumn(categories, categories.syncId);
            await m.addColumn(subCategories, subCategories.syncId);
            await m.addColumn(merchants, merchants.syncId);
            await m.addColumn(merchantRules, merchantRules.syncId);
            await m.addColumn(budgets, budgets.syncId);
            await m.addColumn(recurringTransactions, recurringTransactions.syncId);
            await m.addColumn(transactions, transactions.syncId);
            await _backfillSyncIds();
          }
        },
        // NOTA: l'ordine manuale (drag & drop) di categorie/sottocategorie
        // (v. CategoryDao) è salvato nella tabella Settings già esistente,
        // come elenco di id separati da virgola — nessuna nuova colonna né
        // migrazione di schema necessarie per quella funzionalità.
        beforeOpen: (details) async {
          // Indici UNIQUE parziali su syncId (solo righe non nulle): SQLite
          // non permette ALTER TABLE ADD COLUMN con vincolo UNIQUE inline,
          // quindi l'unicità si applica qui con un indice separato invece che
          // sulla colonna stessa. Idempotente (IF NOT EXISTS), eseguito a ogni
          // apertura del DB così vale sia per installazioni nuove (onCreate)
          // che per upgrade da versioni precedenti (onUpgrade v5).
          for (final table in [
            'categories',
            'sub_categories',
            'merchants',
            'merchant_rules',
            'budgets',
            'recurring_transactions',
            'transactions',
          ]) {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_sync_id '
              'ON $table(sync_id) WHERE sync_id IS NOT NULL',
            );
          }
        },
      );

  /// Assegna un UUID v4 a ogni riga esistente senza `syncId` (migrazione a
  /// v5): una query + un update per riga, volumi bassi (uso personale),
  /// nessun problema di performance. Ogni tabella ha un tipo di riga/Companion
  /// diverso in Drift, quindi si ripete lo stesso blocco per tabella invece
  /// di generalizzare con i generics (più semplice da verificare).
  Future<void> _backfillSyncIds() async {
    const uuid = Uuid();

    final categoryIds = await (selectOnly(categories)
          ..addColumns([categories.id])
          ..where(categories.syncId.isNull()))
        .map((row) => row.read(categories.id)!)
        .get();
    for (final id in categoryIds) {
      await (update(categories)..where((t) => t.id.equals(id)))
          .write(CategoriesCompanion(syncId: Value(uuid.v4())));
    }

    final subCategoryIds = await (selectOnly(subCategories)
          ..addColumns([subCategories.id])
          ..where(subCategories.syncId.isNull()))
        .map((row) => row.read(subCategories.id)!)
        .get();
    for (final id in subCategoryIds) {
      await (update(subCategories)..where((t) => t.id.equals(id)))
          .write(SubCategoriesCompanion(syncId: Value(uuid.v4())));
    }

    final merchantIds = await (selectOnly(merchants)
          ..addColumns([merchants.id])
          ..where(merchants.syncId.isNull()))
        .map((row) => row.read(merchants.id)!)
        .get();
    for (final id in merchantIds) {
      await (update(merchants)..where((t) => t.id.equals(id)))
          .write(MerchantsCompanion(syncId: Value(uuid.v4())));
    }

    final merchantRuleIds = await (selectOnly(merchantRules)
          ..addColumns([merchantRules.id])
          ..where(merchantRules.syncId.isNull()))
        .map((row) => row.read(merchantRules.id)!)
        .get();
    for (final id in merchantRuleIds) {
      await (update(merchantRules)..where((t) => t.id.equals(id)))
          .write(MerchantRulesCompanion(syncId: Value(uuid.v4())));
    }

    final budgetIds = await (selectOnly(budgets)
          ..addColumns([budgets.id])
          ..where(budgets.syncId.isNull()))
        .map((row) => row.read(budgets.id)!)
        .get();
    for (final id in budgetIds) {
      await (update(budgets)..where((t) => t.id.equals(id)))
          .write(BudgetsCompanion(syncId: Value(uuid.v4())));
    }

    final recurringIds = await (selectOnly(recurringTransactions)
          ..addColumns([recurringTransactions.id])
          ..where(recurringTransactions.syncId.isNull()))
        .map((row) => row.read(recurringTransactions.id)!)
        .get();
    for (final id in recurringIds) {
      await (update(recurringTransactions)..where((t) => t.id.equals(id)))
          .write(RecurringTransactionsCompanion(syncId: Value(uuid.v4())));
    }

    final transactionIds = await (selectOnly(transactions)
          ..addColumns([transactions.id])
          ..where(transactions.syncId.isNull()))
        .map((row) => row.read(transactions.id)!)
        .get();
    for (final id in transactionIds) {
      await (update(transactions)..where((t) => t.id.equals(id)))
          .write(TransactionsCompanion(syncId: Value(uuid.v4())));
    }
  }
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
