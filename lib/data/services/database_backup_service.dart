import 'dart:typed_data';

import '../local/database/app_database.dart';

/// Backup completo del database locale su richiesta (Admin > "Esporta
/// backup completo", M43) — stesso principio delle copie manuali del file
/// `.sqlite` fatte finora prima di ogni operazione rischiosa (v. CLAUDE.md,
/// es. `finance_app.sqlite.backup-2026-08-17-pre-m35-merchants-removal`),
/// solo senza dover aprire un terminale/script usa-e-getta ogni volta.
///
/// Copia grezza del file: nessuna cifratura/trasformazione, lo stesso file
/// che l'app userebbe per riaprire il database. Sicura senza precauzioni
/// aggiuntive perché il database NON usa WAL (v. `app_database.dart`,
/// `_openConnection`) — nessun file `-wal`/`-shm` con dati non ancora nel
/// file principale da doversi preoccupare di includere.
class DatabaseBackupService {
  const DatabaseBackupService();

  /// Nome file proposto per il salvataggio, con data e ora (non solo la
  /// data) per non rischiare di sovrascrivere per errore un backup fatto
  /// poco prima nella stessa giornata.
  String suggestedFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Tally-backup-${now.year}-${two(now.month)}-${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.sqlite';
  }

  /// Byte grezzi del file database, da passare a `FilePicker.saveFile`
  /// (stesso pattern già in uso per l'export CSV, v. `export_page.dart`).
  Future<Uint8List> readDatabaseBytes() async {
    final file = await resolveDatabaseFile();
    return file.readAsBytes();
  }
}
