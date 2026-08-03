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

  /// Tabella remota -> insieme delle sue colonne, per simulare `CREATE TABLE
  /// IF NOT EXISTS` (non tocca una tabella "già esistente", stesso
  /// comportamento del vero Turso) e `PRAGMA table_info`/`ALTER TABLE ADD
  /// COLUMN` usati da `_ensureRemoteSchema` per aggiungere colonne a una
  /// tabella remota creata da una versione precedente dello schema. Un test
  /// può pre-seminare qui uno schema "vecchio" (senza le colonne più recenti)
  /// per riprodurre quel bug prima del fix.
  final Map<String, Set<String>> tableColumns = {};

  /// Se impostato, ogni statement (tranne quelli di `_ensureRemoteSchema` —
  /// CREATE TABLE, PRAGMA, ALTER TABLE — che devono sempre riuscire) che
  /// menziona questa tabella lancia un'eccezione: per testare l'isolamento
  /// degli errori tra tabelle.
  String? failTableContaining;

  int executeCallCount = 0;

  /// Se impostato, ogni chiamata a [execute] aspetta questo future prima di
  /// procedere: serve solo nei test sulla rientranza di
  /// `TursoSyncService.syncNow()`, per simulare una richiesta HTTP ancora
  /// "in volo" e controllare deterministicamente la sovrapposizione tra due
  /// syncNow() concorrenti (altrimenti, senza rete vera, ogni execute()
  /// risolverebbe troppo in fretta per poterla osservare).
  Future<void>? blockUntil;

  @override
  Future<List<TursoResult>> execute(List<TursoStatement> statements) async {
    if (blockUntil != null) await blockUntil;
    executeCallCount++;
    final out = <TursoResult>[];
    for (final stmt in statements) {
      final sql = stmt.sql.trim();
      final upper = sql.toUpperCase();
      final isSchemaStatement = upper.startsWith('CREATE TABLE') ||
          upper.startsWith('PRAGMA') ||
          upper.startsWith('ALTER TABLE');
      if (!isSchemaStatement && failTableContaining != null && sql.contains(failTableContaining!)) {
        throw TursoApiException('Errore simulato su $failTableContaining');
      }
      if (upper.startsWith('CREATE TABLE')) {
        final table = RegExp(r'CREATE TABLE IF NOT EXISTS\s+(\w+)', caseSensitive: false)
            .firstMatch(sql)!
            .group(1)!;
        // putIfAbsent, non un assegnamento diretto: come il vero `IF NOT
        // EXISTS`, non deve sovrascrivere uno schema "vecchio" già seminato
        // da un test per simulare una tabella remota preesistente.
        tableColumns.putIfAbsent(table, () => _parseColumnNames(sql));
        out.add(const TursoResult([], []));
      } else if (upper.startsWith('PRAGMA TABLE_INFO')) {
        final table =
            RegExp(r'PRAGMA\s+table_info\((\w+)\)', caseSensitive: false).firstMatch(sql)!.group(1)!;
        final columns = tableColumns[table] ?? const <String>{};
        out.add(TursoResult(['name'], [for (final c in columns) [c]]));
      } else if (upper.startsWith('ALTER TABLE')) {
        final m = RegExp(r'ALTER TABLE\s+(\w+)\s+ADD COLUMN\s+(\w+)', caseSensitive: false)
            .firstMatch(sql)!;
        tableColumns.putIfAbsent(m.group(1)!, () => {}).add(m.group(2)!);
        out.add(const TursoResult([], []));
      } else if (sql.toUpperCase().startsWith('INSERT INTO')) {
        out.add(_handleInsert(sql, stmt.args));
      } else if (sql.toUpperCase().startsWith('SELECT') &&
          sql.contains('WHERE sync_id')) {
        out.add(_handleSelectBySyncId(sql, stmt.args));
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
    _checkColumnsExist(table, columns);
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
    _checkColumnsExist(table, columns);
    final threshold = args[0] as int;

    final store = tables[table] ?? const {};
    final rows = store.values
        .where((row) => (row['updated_at'] as int) > threshold)
        .map((row) => [for (final c in columns) row[c]])
        .toList();
    return TursoResult(columns, rows);
  }

  /// `SELECT <colonne> FROM <tabella> WHERE sync_id = ?`: lookup puntuale per
  /// una singola riga per sync_id (v. `isTransactionDeletionConfirmedRemotely`),
  /// diversa dalla scansione `WHERE updated_at > ?` di push/pull.
  TursoResult _handleSelectBySyncId(String sql, List<Object?> args) {
    final m = RegExp(r'SELECT\s+(.+?)\s+FROM\s+(\w+)\s+WHERE\s+sync_id\s*=\s*\?').firstMatch(sql)!;
    final columns = m.group(1)!.split(',').map((c) => c.trim()).toList();
    final table = m.group(2)!;
    _checkColumnsExist(table, columns);
    final syncId = args[0].toString();

    final row = tables[table]?[syncId];
    if (row == null) return TursoResult(columns, const []);
    return TursoResult(columns, [
      [for (final c in columns) row[c]],
    ]);
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

  /// Riproduce l'errore reale di Turso ("no such column"/"has no column
  /// named") quando uno statement referenzia una colonna assente dallo
  /// schema tracciato — SOLO se lo schema di [table] è tracciato (una
  /// tabella scritta a mano da un test via `tables[...] =` senza mai
  /// passare da `CREATE TABLE`/`tableColumns` non viene verificata: qui non
  /// serve simulare lo schema per quei test, solo per quelli su
  /// `_ensureRemoteSchema`).
  void _checkColumnsExist(String table, Iterable<String> columns) {
    final known = tableColumns[table];
    if (known == null) return;
    for (final c in columns) {
      if (!known.contains(c)) {
        throw TursoApiException('SQLite error: table $table has no column named $c, code: SQLITE_UNKNOWN');
      }
    }
  }

  /// Estrae i nomi colonna dal corpo di un `CREATE TABLE (...)`: primo
  /// token di ogni definizione separata da virgola (basta per lo scopo qui,
  /// nessuna delle definizioni prodotte da `_ensureRemoteSchema` ha virgole
  /// annidate in parentesi).
  Set<String> _parseColumnNames(String createTableSql) {
    final start = createTableSql.indexOf('(');
    final end = createTableSql.lastIndexOf(')');
    final body = createTableSql.substring(start + 1, end);
    return body
        .split(',')
        .map((part) => part.trim().split(RegExp(r'\s+')).first)
        .toSet();
  }
}
