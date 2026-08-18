import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/database_backup_service.dart';

final databaseBackupServiceProvider = Provider<DatabaseBackupService>((ref) {
  return const DatabaseBackupService();
});
