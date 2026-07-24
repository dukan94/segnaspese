/// Stato di sincronizzazione mostrato in UI (v. wireframe: icona in Home).
enum SyncStatus { offline, syncing, synced, error }

/// Servizio responsabile della sincronizzazione multi-dispositivo tramite
/// Turso (libSQL), in modalità "embedded replica": l'app legge/scrive
/// sempre sul database SQLite locale (drift/AppDatabase), questo servizio
/// si occupa solo di tenerlo allineato al database remoto in background.
///
/// NOTA: implementazione completa pianificata per la Milestone M7, dopo
/// che schema e repository saranno stabili (v. progettazione approvata,
/// sezione "Sync multi-dispositivo (Turso)"). Qui definiamo solo il
/// contratto, così il resto del codice può già dipendere da questa
/// interfaccia senza modifiche future.
abstract class SyncService {
  Stream<SyncStatus> get statusStream;

  /// Avvia la sync in background (chiamato all'avvio app e periodicamente).
  Future<void> syncNow();

  /// Configura le credenziali del database Turso (URL + auth token),
  /// inserite dall'utente una tantum nelle Impostazioni.
  Future<void> configure({required String tursoUrl, required String authToken});
}
