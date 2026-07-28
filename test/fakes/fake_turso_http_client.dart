import 'package:finance_app/data/services/turso_http_client.dart';

/// Turso HTTP finto e in-memory per i test di [TursoSyncService]:
/// interpreta le sole forme di SQL che il motore di sync produce davvero
/// (CREATE TABLE, INSERT...ON CONFLICT upsert, SELECT...WHERE updated_at > ?,
/// UPDATE...SET is_deleted — v. turso_sync_service.dart) invece di simulare
/// il protocollo di rete Hrana. Permette di testare push/pull/isolamento
/// errori sul codice di produzione reale ([TursoSyncService.syncNow]) senza
/// rete: si inietta con `TursoSyncService(db, client: FakeTursoHttpClient())`.
class FakeTursoHttpClient extends TursoHttpClient {
  FakeTursoHttpClient() : super(baseUrl: 'fake://test', authToken: 'test');

  /// Tabella remota -> chiave primaria (sync_id o key) -> riga.
  final Map<String, Map<String, Map<String, Object?>>> tables = {};

  /// Se impostato, ogni statement (tranne le CREATE TABLE, che devono
  /// sempre riuscire — v. `_ensureRemoteSchema`) che menziona questa tabella
  /// lancia un'eccezione: per testare l'isolamento degli errori tra tabelle.
  String? failTableContaining;

  int executeCallCount = 0;

  @override
  Future<List<TursoResult>> execute(List<TursoStatement> statements) async {
    executeCallCount++;
    final out = <TursoResult>[];
    for (final stmt in statements) {
      final sql = stmt.sql.trim();
      final isCreateTable = sql.toUpperCase().startsWith('CREATE TABLE');
      if (!isCreateTable && failTableContaining != null && sql.contains(failTableContaining!)) {
        throw TursoApiException('Errore simulato su $failTableContaining');
      }
      if (isCreateTable) {
        out.add(const TursoResult([], []));
      } else if (sql.toUpperCase().startsWith('INSERT INTO')) {
        out.add(_handleInsert(sql, stmt.args));
      } else if (sql.toUpperCase().startsWith('SELECT')) {
        out.add(_handleSelect(sql, stmt.args));
      } else if (sql.toUpperCase().startsWith('UPDATE')) {
        out.add(_handleUpdate(sql, stmt.args));
      } else {
        throw StateError('FakeTursoHttpClient: statement non gestito: $sql');
      }
    }
    return out;
  }

  TursoResult _handleInsert(String sql, List<Object?> args) {
    final table = RegExp(r'INSERT INTO\s+(\w+)').firstMatch(sql)!.group(1)!;
    final columns = RegExp(r'INSERT INTO\s+\w+\s*\(([^)]+)\)')
        .firstMatch(sql)!
        .group(1)!
        .split(',')
        .map((c) => c.trim())
        .toList();
    final row = <String, Object?>{
      for (var i = 0; i < columns.length; i++) columns[i]: args[i],
    };
    final pkValue = row[columns.first].toString();
    final updatedAtIndex = columns.indexOf('updated_at');
    final newUpdatedAt = args[updatedAtIndex] as int;

    final store = tables.putIfAbsent(table, () => {});
    final existing = store[pkValue];
    // Stesso guard "WHERE excluded.updated_at > tbl.updated_at" del vero upsert.
    if (existing == null || (existing['updated_at'] as int) < newUpdatedAt) {
      store[pkValue] = row;
    }
    return const TursoResult([], []);
  }

  TursoResult _handleSelect(String sql, List<Object?> args) {
    final m = RegExp(r'SELECT\s+(.+?)\s+FROM\s+(\w+)\s+WHERE\s+updated_at\s*>\s*\?').firstMatch(sql)!;
    final columns = m.group(1)!.split(',').map((c) => c.trim()).toList();
    final table = m.group(2)!;
    final threshold = args[0] as int;

    final store = tables[table] ?? const {};
    final rows = store.values
        .where((row) => (row['updated_at'] as int) > threshold)
        .map((row) => [for (final c in columns) row[c]])
        .toList();
    return TursoResult(columns, rows);
  }

  /// Unica forma di UPDATE prodotta dal motore di sync: il tombstone dei
  /// doppioni di contenuto scoperti al pull (v. transaction_duplicate_finder.dart).
  TursoResult _handleUpdate(String sql, List<Object?> args) {
    final table = RegExp(r'UPDATE\s+(\w+)').firstMatch(sql)!.group(1)!;
    final newUpdatedAt = args[0];
    final syncId = args[1].toString();
    final expectedUpdatedAt = args[2];

    final row = tables[table]?[syncId];
    if (row != null && row['updated_at'] == expectedUpdatedAt) {
      row['is_deleted'] = 1;
      row['updated_at'] = newUpdatedAt;
    }
    return const TursoResult([], []);
  }
}
