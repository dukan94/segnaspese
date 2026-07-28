import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/database_provider.dart';
import 'core/di/recurring_providers.dart';
import 'core/di/sync_providers.dart';
import 'data/local/seed/dedupe_default_taxonomy.dart';
import 'data/local/seed/repair_orphaned_subcategories.dart';
import 'data/local/seed/seed_runner.dart';
import 'presentation/home/home_providers.dart';

void _logSyncError(Object error, StackTrace stackTrace) {
  debugPrint('Sync Turso fallita (background): $error\n$stackTrace');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Necessario per i formatter di data in locale italiano (v. core/utils).
  await initializeDateFormatting('it_IT');

  final container = ProviderContainer();
  final db = container.read(appDatabaseProvider);

  // Applica i dati di default. Al primo avvio popola categorie,
  // sottocategorie e regole; se la tassonomia di default è cambiata
  // (kSeedVersion) esegue un reset pulito e ripopola (v. seed_runner.dart).
  await runSeed(db);

  // Ripara eventuali doppioni di categorie/sottocategorie/regole di default
  // creati da dispositivi che hanno seedato la tassonomia indipendentemente
  // prima di sincronizzare (v. dedupe_default_taxonomy.dart). Innocuo e
  // veloce quando non ce ne sono.
  await dedupeDefaultTaxonomy(db);

  // Ripara sottocategorie rimaste attive con una categoria padre cancellata
  // (v. repair_orphaned_subcategories.dart). Va dopo dedupeDefaultTaxonomy:
  // pulisce anche eventuali incoerenze che il re-pointing del dedupe stesso
  // potrebbe rivelare.
  await repairOrphanedSubCategories(db);

  // Genera le transazioni dovute dai movimenti ricorrenti attivi (recupera
  // anche le occorrenze arretrate se l'app non veniva aperta da più periodi).
  // v. domain/usecases/recurring/generate_due_recurring.dart
  await container.read(generateDueRecurringProvider).call();

  // Sync Turso (Milestone M7): non deve mai bloccare l'avvio né far
  // crashare l'app se non configurata o offline, quindi fire-and-forget con
  // try/catch (ma loggato, non silenzioso: altrimenti un errore di sync in
  // background non sarebbe mai diagnosticabile). Si ripete ogni 5 minuti
  // mentre l'app resta aperta.
  final syncService = container.read(syncServiceProvider);
  unawaited(syncService.syncNow().catchError(_logSyncError));
  Timer.periodic(const Duration(minutes: 5), (_) {
    unawaited(syncService.syncNow().catchError(_logSyncError));
    // currentMonthTransactionsProvider/currentYearTransactionsProvider
    // calcolano l'intervallo di date una sola volta, alla creazione: senza
    // invalidarli periodicamente, una sessione desktop lasciata aperta a
    // cavallo di un cambio mese/anno continuerebbe a mostrare il riepilogo
    // Home del periodo vecchio.
    container.invalidate(currentMonthTransactionsProvider);
    container.invalidate(currentYearTransactionsProvider);
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FinanceApp(),
    ),
  );
}
