import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database/app_database.dart';

/// Istanza singleton del database, condivisa da tutti i repository
/// (v. progettazione, sezione Architettura: DI tramite Riverpod).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
