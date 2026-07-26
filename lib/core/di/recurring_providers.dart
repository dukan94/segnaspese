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

final addRecurringProvider = Provider<AddRecurring>((ref) {
  return AddRecurring(ref.watch(recurringRepositoryProvider));
});

final updateRecurringProvider = Provider<UpdateRecurring>((ref) {
  return UpdateRecurring(ref.watch(recurringRepositoryProvider));
});

final deleteRecurringProvider = Provider<DeleteRecurring>((ref) {
  return DeleteRecurring(ref.watch(recurringRepositoryProvider));
});

final setRecurringActiveProvider = Provider<SetRecurringActive>((ref) {
  return SetRecurringActive(ref.watch(recurringRepositoryProvider));
});

/// Job di generazione automatica delle transazioni dovute (invocato all'avvio).
final generateDueRecurringProvider = Provider<GenerateDueRecurring>((ref) {
  return GenerateDueRecurring(ref.watch(recurringRepositoryProvider));
});
