import '../local/database/daos/transaction_dao.dart';
import 'turso_sync_service.dart';

/// Esito di un'eliminazione definitiva puntuale (v. [SafeTransactionDeletionService.hardDeleteTransaction]).
class HardDeleteOutcome {
  const HardDeleteOutcome({required this.deleted, this.reason});

  /// true se la transazione è stata eliminata per sempre. Se false, la
  /// transazione resta soft-deleted (nascosta, non più visibile) ma NON
  /// eliminata fisicamente — [reason] spiega perché.
  final bool deleted;
  final String? reason;
}

/// Esito di una pulizia bulk (v. [SafeTransactionDeletionService.purgeSoftDeletedTransactions]).
class PurgeOutcome {
  const PurgeOutcome({required this.purgedCount, required this.skippedCount});

  final int purgedCount;

  /// Quante transazioni già soft-deleted sono state lasciate stare perché il
  /// server non ne confermava ancora la cancellazione.
  final int skippedCount;
}

/// Unico punto d'accesso per eliminare per sempre una transazione (bypassa
/// il soft delete, irreversibile): usato solo dal pannello Admin.
///
/// Non basta che `TursoSyncService.syncNow()` non lanci eccezioni per essere
/// sicuri che il server remoto sappia di una cancellazione: il push di
/// quella riga potrebbe essere stato scartato in silenzio (FK non ancora
/// sincronizzata), l'upsert last-write-wins potrebbe non aver aggiornato
/// nulla per clock skew, o un'altra sync in corso potrebbe aver fotografato
/// le righe da spingere prima di questa modifica. L'unica garanzia
/// autorevole è leggere DIRETTAMENTE dal server se quella riga risulta
/// davvero cancellata (`TursoSyncService.isTransactionDeletionConfirmedRemotely`)
/// — è quello che questo servizio fa prima di ogni hard delete, con qualche
/// tentativo di sync in più se il primo non basta (utile con più
/// dispositivi attivi, dove una sync di sfondo può sovrapporsi spesso).
class SafeTransactionDeletionService {
  /// [maxSyncAttempts]/[retryDelay] solo per i test: permettono di ridurre
  /// l'attesa reale (2s in produzione, 3 tentativi) senza rallentare la
  /// suite quando si simula un `syncNow()` che continua a fallire.
  SafeTransactionDeletionService(
    this._dao,
    this._syncService, {
    int maxSyncAttempts = 3,
    Duration retryDelay = const Duration(seconds: 2),
  })  : _maxSyncAttempts = maxSyncAttempts,
        _retryDelay = retryDelay;

  final TransactionDao _dao;
  final TursoSyncService _syncService;
  final int _maxSyncAttempts;
  final Duration _retryDelay;

  /// Prova a sincronizzare fino a [_maxSyncAttempts] volte, ignorando errori
  /// intermedi: serve solo a dare al push la massima occasione di arrivare
  /// al server. Non è questa la garanzia di sicurezza — lo è la verifica
  /// riga per riga che segue, che resta autorevole anche se ogni tentativo
  /// qui fallisce.
  Future<void> _bestEffortSync() async {
    if (!await _syncService.isConfigured()) return;
    for (var attempt = 1; attempt <= _maxSyncAttempts; attempt++) {
      try {
        await _syncService.syncNow();
        return;
      } catch (_) {
        if (attempt < _maxSyncAttempts) {
          await Future.delayed(_retryDelay);
        }
      }
    }
  }

  Future<bool> _confirmedRemotely(int id) async {
    if (!await _syncService.isConfigured()) return true;
    try {
      return await _syncService.isTransactionDeletionConfirmedRemotely(id);
    } catch (_) {
      // Impossibile verificare (es. rete assente proprio ora): per
      // sicurezza NON si considera confermata. Fallire "chiuso" (non
      // eliminare) è sempre la scelta giusta qui, mai il contrario.
      return false;
    }
  }

  /// Elimina per sempre la transazione [id]: soft delete, poi (se Turso è
  /// configurato) sync + verifica sul server, e solo a conferma ottenuta
  /// l'eliminazione fisica. Se il server non conferma, la transazione resta
  /// soft-deleted (nascosta ma recuperabile solo da "Pulisci database" più
  /// tardi, non da qui: la ricerca in Admin cerca solo tra le attive).
  Future<HardDeleteOutcome> hardDeleteTransaction(int id) async {
    await _dao.softDelete(id);
    await _bestEffortSync();
    if (!await _confirmedRemotely(id)) {
      return const HardDeleteOutcome(
        deleted: false,
        reason: 'Il server non conferma ancora la cancellazione. La '
            'transazione resta nascosta; riprova più tardi da "Pulisci '
            'database".',
      );
    }
    await _dao.hardDelete(id);
    return const HardDeleteOutcome(deleted: true);
  }

  /// Elimina per sempre tutte le transazioni già soft-deleted PER CUI il
  /// server conferma la cancellazione; lascia stare (senza errore, solo
  /// segnalandolo nel conteggio) quelle non ancora confermate.
  Future<PurgeOutcome> purgeSoftDeletedTransactions() async {
    await _bestEffortSync();
    final ids = await _dao.getSoftDeletedIds();
    var purged = 0;
    var skipped = 0;
    for (final id in ids) {
      if (await _confirmedRemotely(id)) {
        await _dao.hardDelete(id);
        purged++;
      } else {
        skipped++;
      }
    }
    return PurgeOutcome(purgedCount: purged, skippedCount: skipped);
  }
}
