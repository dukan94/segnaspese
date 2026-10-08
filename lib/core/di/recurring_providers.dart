import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/daos/recurring_dao.dart';
import '../../data/repositories_impl/recurring_repository_impl.dart';
import '../../domain/entities/recurring_entity.dart';
import '../../domain/repositories/recurring_repository.dart';
import '../../domain/usecases/recurring/add_recurring.dart';
import '../../domain/usecases/recurring/delete_recurring.dart';
import '../../domain/usecases/recurring/generate_due_recurring.dart';
import '../../domain/usecases/recurring/set_recurring_active.dart';
import '../../domain/usecases/recurring/update_recurring.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

/// Logga un fallimento della sync scatenata dopo un salvataggio (M58) —
/// stesso pattern fire-and-forget di `transaction_providers.dart` (M32),
/// mai mostrato all'utente.
void _logPostSaveSyncError(Object error, StackTrace stackTrace) {
  debugPrint('Sync Turso fallita (dopo salvataggio ricorrenza): $error\n$stackTrace');
}

/// DAO delle ricorrenze, ricavato dall'istanza condivisa di [AppDatabase].
final recurringDaoProvider = Provider<RecurringDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.recurringDao;
});

/// Repository astratto: il resto dell'app dipende solo da
/// [RecurringRepository], mai da [RecurringRepositoryImpl] direttamente.
final recurringRepositoryProvider = Provider<RecurringRepository>((ref) {
  return RecurringRepositoryImpl(ref.watch(recurringDaoProvider));
});

// --- Letture reattive ---

/// Tutte le ricorrenze non cancellate (attive prima, poi in pausa).
final allRecurringProvider = StreamProvider<List<RecurringEntity>>((ref) {
  return ref.watch(recurringRepositoryProvider).watchAll();
});

// --- Scrittura (usecase) ---

/// M58: dopo il salvataggio locale lancia anche una sync Turso in
/// background — stesso trattamento di transazioni (M32) e budget (M56),
/// mancante qui da sempre.
final addRecurringProvider =
    Provider<Future<int> Function(RecurringEntity)>((ref) {
  final useCase = AddRecurring(ref.watch(recurringRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (recurring) async {
    final id = await useCase.call(recurring);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
    return id;
  };
});

/// M58: v. [addRecurringProvider].
final updateRecurringProvider =
    Provider<Future<void> Function(RecurringEntity)>((ref) {
  final useCase = UpdateRecurring(ref.watch(recurringRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (recurring) async {
    await useCase.call(recurring);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addRecurringProvider].
final deleteRecurringProvider = Provider<Future<void> Function(int)>((ref) {
  final useCase = DeleteRecurring(ref.watch(recurringRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (id) async {
    await useCase.call(id);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addRecurringProvider].
final setRecurringActiveProvider =
    Provider<Future<void> Function(int, bool)>((ref) {
  final useCase = SetRecurringActive(ref.watch(recurringRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (id, active) async {
    await useCase.call(id, active);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// Job di generazione automatica delle transazioni dovute (invocato
/// all'avvio). Niente sync qui (M58): all'avvio parte già quella di sistema.
final generateDueRecurringProvider = Provider<GenerateDueRecurring>((ref) {
  return GenerateDueRecurring(ref.watch(recurringRepositoryProvider));
});
