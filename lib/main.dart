import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/di/database_provider.dart';
import 'core/di/recurring_providers.dart';
import 'data/local/seed/seed_runner.dart';

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

  // Genera le transazioni dovute dai movimenti ricorrenti attivi (recupera
  // anche le occorrenze arretrate se l'app non veniva aperta da più periodi).
  // v. domain/usecases/recurring/generate_due_recurring.dart
  await container.read(generateDueRecurringProvider).call();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FinanceApp(),
    ),
  );
}
