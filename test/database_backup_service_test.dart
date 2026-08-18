import 'package:finance_app/data/services/database_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `suggestedFileName` (M43) — l'unica vera logica del servizio,
/// oltre alla lettura del file (wiring sottile su `resolveDatabaseFile`/
/// `dart:io`, non testata a parte, stesso principio già seguito per la
/// sync immediata di `addTransactionProvider`, v. CLAUDE.md M32/M42).
void main() {
  const service = DatabaseBackupService();

  test('include data e ora con zero-padding, estensione .sqlite', () {
    final name = service.suggestedFileName(DateTime(2026, 8, 3, 9, 5));
    expect(name, 'Tally-backup-2026-08-03-0905.sqlite');
  });

  test('due chiamate a distanza di un minuto producono nomi diversi', () {
    final a = service.suggestedFileName(DateTime(2026, 8, 18, 14, 30));
    final b = service.suggestedFileName(DateTime(2026, 8, 18, 14, 31));
    expect(a, isNot(b));
  });
}
