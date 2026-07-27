import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/sync_service.dart';
import '../../data/services/turso_sync_service.dart';
import 'database_provider.dart';

/// Istanza singleton del servizio di sync Turso (Milestone M7), condivisa
/// dalla schermata Impostazioni > Sync e dall'icona di stato in Home.
final syncServiceProvider = Provider<TursoSyncService>((ref) {
  final service = TursoSyncService(ref.watch(appDatabaseProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Stato corrente della sync (per l'icona in Home, v. [SyncStatus]).
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncServiceProvider).statusStream;
});
