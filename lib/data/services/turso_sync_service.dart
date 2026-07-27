import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../local/database/app_database.dart';
import '../local/database/tables/budgets_table.dart';
import '../local/database/tables/categories_table.dart';
import '../local/database/tables/recurring_table.dart';
import 'sync_service.dart';
import 'turso_http_client.dart';

/// Riassume gli errori di uno o più passi push/pull falliti durante un
/// ciclo di [TursoSyncService.syncNow]. I passi andati a buon fine hanno
/// comunque avanzato le rispettive filigrane; solo quelli qui elencati
/// verranno ritentati al ciclo successivo (v. `_syncNowInner`).
class TursoSyncPartialFailureException implements Exception {
  TursoSyncPartialFailureException(this.stepErrors);

  final Map<String, Object> stepErrors;

  @override
  String toString() =>
      'TursoSyncPartialFailureException: ${stepErrors.length} passo/i falliti '
      '(${stepErrors.keys.join(', ')})';
}

/// Implementazione di [SyncService] basata sull'API HTTP di Turso (v.
/// turso_http_client.dart). Sincronizza 6 delle 7 tabelle sincronizzabili:
/// Categories, SubCategories, MerchantRules, Budgets, RecurringTransactions,
/// Transactions. La tabella Merchants ha lo schema pronto (`syncId`) ma
/// nessun DAO/repository/flusso UI ancora collegato (in attesa di M3/M6:
/// scansione scontrini), quindi non ha ancora dati da sincronizzare.
///
/// Ogni tabella locale ha una controparte remota `sync_<tabella>` con schema
/// "sync-friendly": stesse colonne, ma le foreign key intere locali (es.
/// `categoryId`) diventano colonne testuali (`category_sync_id`) valorizzate
/// con lo `syncId` della riga referenziata — gli id interi autoincrementali
/// locali NON sono validi tra dispositivi diversi (v. Transactions.syncId
/// per i dettagli). `receiptImagePath` (path locale di una foto) e
/// `merchantId` (tabella Merchants non ancora popolata) sono volutamente
/// esclusi dalla sincronizzazione.
///
/// Risoluzione conflitti: last-write-wins basato su `updatedAt`, applicata
/// sia lato server (upsert push con `WHERE excluded.updated_at > ...`) sia
/// lato client al pull (si scrive solo se il remoto è più recente).
/// Assunzione accettata: si fida dell'orologio locale di ogni dispositivo,
/// senza protezione da clock skew (un dispositivo con l'ora indietro perde
/// sistematicamente i conflitti) — ragionevole per uso personale su
/// dispositivi con sync orario automatico (Android/Windows), non robusta in
/// generale.
///
/// Atomicità: un batch di push (`TursoHttpClient.execute`) NON è avvolto in
/// una transazione SQL lato server — se lo statement K fallisce dopo che
/// 1..K-1 sono già stati applicati, l'eccezione risalendo impedisce la
/// scrittura della filigrana per quella tabella (v. ogni `_pushX`/`_pullX`),
/// quindi l'intero batch (incluse le righe 1..K-1 già applicate) verrà
/// rimandato al ciclo successivo. Questo è corretto e sicuro solo perché
/// ogni upsert è idempotente (`WHERE excluded.updated_at > ...`): riapplicare
/// una riga già scritta con lo stesso `updated_at` non ha alcun effetto.
/// Invariante da preservare in futuro: la filigrana di una tabella deve
/// avanzare SOLO dopo che il relativo batch è stato inviato con successo.
class TursoSyncService implements SyncService {
  TursoSyncService(this._db, {FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final AppDatabase _db;
  final FlutterSecureStorage _secureStorage;

  static const _urlKey = 'turso_url';
  static const _tokenKey = 'turso_auth_token';

  TursoHttpClient? _client;
  final _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _currentStatus = SyncStatus.offline;

  /// Riproduce subito l'ultimo stato noto a ogni nuovo ascoltatore (l'icona
  /// in Home non deve restare "in caricamento" finché non parte una sync),
  /// poi continua con gli aggiornamenti live.
  @override
  Stream<SyncStatus> get statusStream async* {
    yield _currentStatus;
    yield* _statusController.stream;
  }

  void _setStatus(SyncStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  /// true se URL e auth token sono già stati salvati (v. [configure]).
  Future<bool> isConfigured() async {
    final url = await _secureStorage.read(key: _urlKey);
    final token = await _secureStorage.read(key: _tokenKey);
    return url != null && url.isNotEmpty && token != null && token.isNotEmpty;
  }

  @override
  Future<void> configure({required String tursoUrl, required String authToken}) async {
    await _secureStorage.write(key: _urlKey, value: tursoUrl);
    await _secureStorage.write(key: _tokenKey, value: authToken);
    _client = TursoHttpClient(baseUrl: tursoUrl, authToken: authToken);
  }

  Future<bool> _ensureClient() async {
    if (_client != null) return true;
    final url = await _secureStorage.read(key: _urlKey);
    final token = await _secureStorage.read(key: _tokenKey);
    if (url == null || url.isEmpty || token == null || token.isEmpty) return false;
    _client = TursoHttpClient(baseUrl: url, authToken: token);
    return true;
  }

  bool _syncing = false;

  @override
  Future<void> syncNow() async {
    // Senza questa guardia, un pausa/ripresa ravvicinati (v. app.dart) o il
    // timer periodico che scatta mentre una sync precedente è ancora in
    // corso potevano avviare due syncNow() in parallelo: non corrompono i
    // dati (upsert idempotenti, i pull scartano righe non più recenti), ma
    // sprecano chiamate HTTP verso Turso e possono far "sfarfallare" lo
    // stato mostrato in UI.
    if (_syncing) return;
    _syncing = true;
    try {
      await _syncNowInner();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncNowInner() async {
    if (!await _ensureClient()) {
      _setStatus(SyncStatus.offline);
      return;
    }
    _setStatus(SyncStatus.syncing);

    // Se la creazione delle tabelle remote fallisce, nessun passo successivo
    // può funzionare comunque: qui un errore blocca subito l'intero ciclo.
    try {
      await _ensureRemoteSchema();
    } catch (_) {
      _setStatus(SyncStatus.error);
      rethrow;
    }

    // Ogni passo push/pull è isolato nel proprio try/catch: un errore su una
    // singola tabella (es. una riga che Turso rifiuta) non deve impedire agli
    // altri passi di girare. Senza questo isolamento, un errore persistente
    // su una tabella bloccherebbe per sempre anche tutte le altre — inclusi i
    // pull che portano le modifiche fatte da altri dispositivi — perché la
    // filigrana di quella tabella non avanza mai e lo stesso errore si
    // ripeterebbe identico a ogni ciclo successivo.
    final failedSteps = <String, Object>{};
    Future<void> runStep(String name, Future<void> Function() step) async {
      try {
        await step();
      } catch (e) {
        failedSteps[name] = e;
      }
    }

    // Push: l'ordine non è rilevante, ogni riga traduce le proprie FK
    // guardando i genitori in locale, che esistono sempre (vincoli FK locali).
    await runStep('push_categories', _pushCategories);
    await runStep('push_subcategories', _pushSubCategories);
    await runStep('push_merchant_rules', _pushMerchantRules);
    await runStep('push_budgets', _pushBudgets);
    await runStep('push_recurring', _pushRecurring);
    await runStep('push_transactions', _pushTransactions);
    await runStep('push_app_settings', _pushAppSettings);

    // Pull: l'ordine conta, i genitori vanno applicati prima dei figli così
    // le foreign key remote si traducono sempre in id locali già esistenti.
    // Se il pull di un genitore fallisce, i pull dei figli comunque provano:
    // le loro righe con FK non risolvibile vengono rimandate al giro
    // successivo dalla logica già presente in ciascun _pullX (v. filigrana).
    await runStep('pull_categories', _pullCategories);
    await runStep('pull_subcategories', _pullSubCategories);
    await runStep('pull_merchant_rules', _pullMerchantRules);
    await runStep('pull_budgets', _pullBudgets);
    await runStep('pull_recurring', _pullRecurring);
    await runStep('pull_transactions', _pullTransactions);
    await runStep('pull_app_settings', _pullAppSettings);

    if (failedSteps.isEmpty) {
      _setStatus(SyncStatus.synced);
    } else {
      _setStatus(SyncStatus.error);
      throw TursoSyncPartialFailureException(failedSteps);
    }
  }

  void dispose() => _statusController.close();

  // --- Schema remoto (idempotente, eseguito a ogni sync) ---

  Future<void> _ensureRemoteSchema() async {
    await _client!.execute(const [
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_categories (
          sync_id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL,
          type INTEGER NOT NULL, color INTEGER NOT NULL, is_default INTEGER NOT NULL,
          updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_subcategories (
          sync_id TEXT PRIMARY KEY, category_sync_id TEXT NOT NULL, name TEXT NOT NULL,
          icon TEXT NOT NULL, updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_merchant_rules (
          sync_id TEXT PRIMARY KEY, pattern TEXT NOT NULL, category_sync_id TEXT NOT NULL,
          sub_category_sync_id TEXT, priority INTEGER NOT NULL, is_user_defined INTEGER NOT NULL,
          updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_budgets (
          sync_id TEXT PRIMARY KEY, category_sync_id TEXT, period INTEGER NOT NULL,
          amount REAL NOT NULL, start_date INTEGER NOT NULL,
          updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_recurring (
          sync_id TEXT PRIMARY KEY, description TEXT NOT NULL, amount REAL NOT NULL,
          type INTEGER NOT NULL, category_sync_id TEXT NOT NULL, sub_category_sync_id TEXT,
          frequency INTEGER NOT NULL, day_of_month INTEGER, next_occurrence INTEGER NOT NULL,
          active INTEGER NOT NULL, updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_transactions (
          sync_id TEXT PRIMARY KEY, date INTEGER NOT NULL, amount REAL NOT NULL,
          type INTEGER NOT NULL, category_sync_id TEXT NOT NULL, sub_category_sync_id TEXT,
          note TEXT, is_extraordinary INTEGER NOT NULL, is_refund INTEGER NOT NULL,
          recurring_sync_id TEXT, refund_of_sync_id TEXT,
          updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL
        )
      '''),
      TursoStatement('''
        CREATE TABLE IF NOT EXISTS sync_app_settings (
          key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL
        )
      '''),
    ]);
  }

  // --- Helpers di conversione ---

  int _boolToInt(bool b) => b ? 1 : 0;
  bool _intToBool(Object? v) => v == 1 || v == true;
  int _epoch(DateTime dt) => dt.millisecondsSinceEpoch;
  DateTime _fromEpoch(Object? v) => DateTime.fromMillisecondsSinceEpoch(v as int);

  /// Ultimo istante sincronizzato per [key]. Le query di push/pull la usano
  /// come `isBiggerOrEqualValue(since.add(1ms))`, perché Drift non espone una
  /// variante "strettamente maggiore": senza il +1ms la riga con l'updatedAt
  /// esatto del watermark verrebbe riselezionata a ogni sync successiva.
  Future<DateTime> _readWatermark(String key) async {
    final row = await (_db.select(_db.settings)..where((s) => s.key.equals('sync_$key')))
        .getSingleOrNull();
    if (row == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(int.parse(row.value));
  }

  Future<void> _writeWatermark(String key, DateTime value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'sync_$key',
            value: value.millisecondsSinceEpoch.toString(),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  // --- Traduzione FK locali <-> syncId remoti ---

  Future<String?> _categorySyncId(int? id) async {
    if (id == null) return null;
    final row = await (_db.select(_db.categories)..where((c) => c.id.equals(id))).getSingleOrNull();
    return row?.syncId;
  }

  Future<int?> _categoryIdFor(String? syncId) async {
    if (syncId == null) return null;
    final row = await (_db.select(_db.categories)..where((c) => c.syncId.equals(syncId))).getSingleOrNull();
    return row?.id;
  }

  Future<String?> _subCategorySyncId(int? id) async {
    if (id == null) return null;
    final row =
        await (_db.select(_db.subCategories)..where((s) => s.id.equals(id))).getSingleOrNull();
    return row?.syncId;
  }

  Future<int?> _subCategoryIdFor(String? syncId) async {
    if (syncId == null) return null;
    final row = await (_db.select(_db.subCategories)..where((s) => s.syncId.equals(syncId)))
        .getSingleOrNull();
    return row?.id;
  }

  Future<String?> _recurringSyncId(int? id) async {
    if (id == null) return null;
    final row = await (_db.select(_db.recurringTransactions)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    return row?.syncId;
  }

  Future<int?> _recurringIdFor(String? syncId) async {
    if (syncId == null) return null;
    final row = await (_db.select(_db.recurringTransactions)..where((r) => r.syncId.equals(syncId)))
        .getSingleOrNull();
    return row?.id;
  }

  Future<String?> _transactionSyncId(int? id) async {
    if (id == null) return null;
    final row =
        await (_db.select(_db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.syncId;
  }

  Future<int?> _transactionIdFor(String? syncId) async {
    if (syncId == null) return null;
    final row =
        await (_db.select(_db.transactions)..where((t) => t.syncId.equals(syncId))).getSingleOrNull();
    return row?.id;
  }

  // --- Categories ---

  Future<void> _pushCategories() async {
    final since = await _readWatermark('push_categories');
    final rows = await (_db.select(_db.categories)..where((c) => c.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1)))))
        .get();
    final dirty = rows.where((r) => r.syncId != null).toList();
    if (dirty.isEmpty) return;

    await _client!.execute([
      for (final r in dirty)
        TursoStatement(
          '''
          INSERT INTO sync_categories (sync_id, name, icon, type, color, is_default, updated_at, is_deleted)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(sync_id) DO UPDATE SET
            name=excluded.name, icon=excluded.icon, type=excluded.type, color=excluded.color,
            is_default=excluded.is_default, updated_at=excluded.updated_at, is_deleted=excluded.is_deleted
          WHERE excluded.updated_at > sync_categories.updated_at
          ''',
          [
            r.syncId, r.name, r.icon, r.type.index, r.color,
            _boolToInt(r.isDefault), _epoch(r.updatedAt), _boolToInt(r.isDeleted),
          ],
        ),
    ]);
    await _writeWatermark(
      'push_categories',
      dirty.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullCategories() async {
    final since = await _readWatermark('pull_categories');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT sync_id, name, icon, type, color, is_default, updated_at, is_deleted '
        'FROM sync_categories WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final syncId = row['sync_id'] as String;
      final updatedAt = _fromEpoch(row['updated_at']);
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;

      final existing =
          await (_db.select(_db.categories)..where((c) => c.syncId.equals(syncId))).getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      final companion = CategoriesCompanion(
        name: Value(row['name'] as String),
        icon: Value(row['icon'] as String),
        type: Value(TransactionKind.values[row['type'] as int]),
        color: Value(row['color'] as int),
        isDefault: Value(_intToBool(row['is_default'])),
        updatedAt: Value(updatedAt),
        isDeleted: Value(_intToBool(row['is_deleted'])),
        syncId: Value(syncId),
      );
      if (existing == null) {
        await _db.into(_db.categories).insert(companion);
      } else {
        await (_db.update(_db.categories)..where((c) => c.id.equals(existing.id))).write(companion);
      }
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_categories', maxUpdatedAt);
  }

  // --- SubCategories ---

  Future<void> _pushSubCategories() async {
    final since = await _readWatermark('push_subcategories');
    final rows = await (_db.select(_db.subCategories)
          ..where((s) => s.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1)))))
        .get();
    final dirty = rows.where((r) => r.syncId != null).toList();
    if (dirty.isEmpty) return;

    final statements = <TursoStatement>[];
    // Solo le righe effettivamente incluse in `statements` avanzano la
    // filigrana (stesso pattern di _pushBudgets): una riga scartata perché il
    // genitore non ha ancora un syncId non va considerata "già gestita",
    // altrimenti non verrebbe più riproposta ai giri successivi.
    final processed = <SubCategory>[];
    for (final r in dirty) {
      final categorySyncId = await _categorySyncId(r.categoryId);
      if (categorySyncId == null) continue; // genitore senza syncId: non dovrebbe succedere
      processed.add(r);
      statements.add(TursoStatement(
        '''
        INSERT INTO sync_subcategories (sync_id, category_sync_id, name, icon, updated_at, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_id) DO UPDATE SET
          category_sync_id=excluded.category_sync_id, name=excluded.name, icon=excluded.icon,
          updated_at=excluded.updated_at, is_deleted=excluded.is_deleted
        WHERE excluded.updated_at > sync_subcategories.updated_at
        ''',
        [r.syncId, categorySyncId, r.name, r.icon, _epoch(r.updatedAt), _boolToInt(r.isDeleted)],
      ));
    }
    if (processed.isEmpty) return;
    await _client!.execute(statements);
    await _writeWatermark(
      'push_subcategories',
      processed.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullSubCategories() async {
    final since = await _readWatermark('pull_subcategories');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT sync_id, category_sync_id, name, icon, updated_at, is_deleted '
        'FROM sync_subcategories WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final syncId = row['sync_id'] as String;
      final updatedAt = _fromEpoch(row['updated_at']);

      final categoryId = await _categoryIdFor(row['category_sync_id'] as String?);
      // Il genitore non è (ancora) risolvibile: la filigrana NON deve
      // avanzare oltre questa riga, altrimenti la successiva SELECT
      // "WHERE updated_at > filigrana" la escluderebbe per sempre — il
      // "si ritenta al prossimo giro" sarebbe falso (bug corretto qui).
      if (categoryId == null) continue;
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;

      final existing = await (_db.select(_db.subCategories)..where((s) => s.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      final companion = SubCategoriesCompanion(
        categoryId: Value(categoryId),
        name: Value(row['name'] as String),
        icon: Value(row['icon'] as String),
        updatedAt: Value(updatedAt),
        isDeleted: Value(_intToBool(row['is_deleted'])),
        syncId: Value(syncId),
      );
      if (existing == null) {
        await _db.into(_db.subCategories).insert(companion);
      } else {
        await (_db.update(_db.subCategories)..where((s) => s.id.equals(existing.id))).write(companion);
      }
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_subcategories', maxUpdatedAt);
  }

  // --- MerchantRules ---

  Future<void> _pushMerchantRules() async {
    final since = await _readWatermark('push_merchant_rules');
    final rows = await (_db.select(_db.merchantRules)
          ..where((r) => r.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1)))))
        .get();
    final dirty = rows.where((r) => r.syncId != null).toList();
    if (dirty.isEmpty) return;

    final statements = <TursoStatement>[];
    // V. commento in _pushSubCategories: la filigrana avanza solo sulle righe
    // effettivamente processate, non su tutte le candidate.
    final processed = <MerchantRule>[];
    for (final r in dirty) {
      final categorySyncId = await _categorySyncId(r.categoryId);
      if (categorySyncId == null) continue;
      processed.add(r);
      final subCategorySyncId = await _subCategorySyncId(r.subCategoryId);
      statements.add(TursoStatement(
        '''
        INSERT INTO sync_merchant_rules
          (sync_id, pattern, category_sync_id, sub_category_sync_id, priority, is_user_defined, updated_at, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_id) DO UPDATE SET
          pattern=excluded.pattern, category_sync_id=excluded.category_sync_id,
          sub_category_sync_id=excluded.sub_category_sync_id, priority=excluded.priority,
          is_user_defined=excluded.is_user_defined, updated_at=excluded.updated_at, is_deleted=excluded.is_deleted
        WHERE excluded.updated_at > sync_merchant_rules.updated_at
        ''',
        [
          r.syncId, r.pattern, categorySyncId, subCategorySyncId, r.priority,
          _boolToInt(r.isUserDefined), _epoch(r.updatedAt), _boolToInt(r.isDeleted),
        ],
      ));
    }
    if (processed.isEmpty) return;
    await _client!.execute(statements);
    await _writeWatermark(
      'push_merchant_rules',
      processed.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullMerchantRules() async {
    final since = await _readWatermark('pull_merchant_rules');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT sync_id, pattern, category_sync_id, sub_category_sync_id, priority, is_user_defined, '
        'updated_at, is_deleted FROM sync_merchant_rules WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final syncId = row['sync_id'] as String;
      final updatedAt = _fromEpoch(row['updated_at']);

      final categoryId = await _categoryIdFor(row['category_sync_id'] as String?);
      // V. commento in _pullSubCategories: non avanzare la filigrana oltre
      // una riga il cui genitore non è ancora risolvibile.
      if (categoryId == null) continue;
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;
      final subCategoryId = await _subCategoryIdFor(row['sub_category_sync_id'] as String?);

      final existing = await (_db.select(_db.merchantRules)..where((r) => r.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      final companion = MerchantRulesCompanion(
        pattern: Value(row['pattern'] as String),
        categoryId: Value(categoryId),
        subCategoryId: Value(subCategoryId),
        priority: Value(row['priority'] as int),
        isUserDefined: Value(_intToBool(row['is_user_defined'])),
        updatedAt: Value(updatedAt),
        isDeleted: Value(_intToBool(row['is_deleted'])),
        syncId: Value(syncId),
      );
      if (existing == null) {
        await _db.into(_db.merchantRules).insert(companion);
      } else {
        await (_db.update(_db.merchantRules)..where((r) => r.id.equals(existing.id))).write(companion);
      }
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_merchant_rules', maxUpdatedAt);
  }

  // --- Budgets ---

  Future<void> _pushBudgets() async {
    final since = await _readWatermark('push_budgets');
    final rows =
        await (_db.select(_db.budgets)..where((b) => b.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1))))).get();
    final dirty = rows.where((r) => r.syncId != null).toList();
    if (dirty.isEmpty) return;

    final statements = <TursoStatement>[];
    // Solo le righe effettivamente incluse in `statements` avanzano la
    // filigrana: se la si calcolasse su `dirty` (tutte le candidate), una
    // riga scartata perché non ancora risolvibile verrebbe considerata
    // "già gestita" e non più riproposta ai giri successivi.
    final processed = <Budget>[];
    for (final r in dirty) {
      final categorySyncId = await _categorySyncId(r.categoryId);
      // categoryId nullo è legittimo (budget totale del mese, non per
      // categoria): va distinto dal caso "categoria reale ma non ancora
      // risolvibile", altrimenti quest'ultimo verrebbe inviato come budget
      // globale invece di essere rimandato al prossimo giro.
      if (r.categoryId != null && categorySyncId == null) continue;
      processed.add(r);
      statements.add(TursoStatement(
        '''
        INSERT INTO sync_budgets (sync_id, category_sync_id, period, amount, start_date, updated_at, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_id) DO UPDATE SET
          category_sync_id=excluded.category_sync_id, period=excluded.period, amount=excluded.amount,
          start_date=excluded.start_date, updated_at=excluded.updated_at, is_deleted=excluded.is_deleted
        WHERE excluded.updated_at > sync_budgets.updated_at
        ''',
        [
          r.syncId, categorySyncId, r.period.index, r.amount,
          _epoch(r.startDate), _epoch(r.updatedAt), _boolToInt(r.isDeleted),
        ],
      ));
    }
    if (processed.isEmpty) return;
    await _client!.execute(statements);
    await _writeWatermark(
      'push_budgets',
      processed.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullBudgets() async {
    final since = await _readWatermark('pull_budgets');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT sync_id, category_sync_id, period, amount, start_date, updated_at, is_deleted '
        'FROM sync_budgets WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final syncId = row['sync_id'] as String;
      final updatedAt = _fromEpoch(row['updated_at']);
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;

      final categoryId = await _categoryIdFor(row['category_sync_id'] as String?);

      final existing =
          await (_db.select(_db.budgets)..where((b) => b.syncId.equals(syncId))).getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      final companion = BudgetsCompanion(
        categoryId: Value(categoryId),
        period: Value(BudgetPeriod.values[row['period'] as int]),
        amount: Value((row['amount'] as num).toDouble()),
        startDate: Value(_fromEpoch(row['start_date'])),
        updatedAt: Value(updatedAt),
        isDeleted: Value(_intToBool(row['is_deleted'])),
        syncId: Value(syncId),
      );
      if (existing == null) {
        await _db.into(_db.budgets).insert(companion);
      } else {
        await (_db.update(_db.budgets)..where((b) => b.id.equals(existing.id))).write(companion);
      }
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_budgets', maxUpdatedAt);
  }

  // --- RecurringTransactions ---

  Future<void> _pushRecurring() async {
    final since = await _readWatermark('push_recurring');
    final rows = await (_db.select(_db.recurringTransactions)
          ..where((r) => r.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1)))))
        .get();
    final dirty = rows.where((r) => r.syncId != null).toList();
    if (dirty.isEmpty) return;

    final statements = <TursoStatement>[];
    // V. commento in _pushSubCategories: la filigrana avanza solo sulle righe
    // effettivamente processate, non su tutte le candidate.
    final processed = <RecurringTransaction>[];
    for (final r in dirty) {
      final categorySyncId = await _categorySyncId(r.categoryId);
      if (categorySyncId == null) continue;
      processed.add(r);
      final subCategorySyncId = await _subCategorySyncId(r.subCategoryId);
      statements.add(TursoStatement(
        '''
        INSERT INTO sync_recurring
          (sync_id, description, amount, type, category_sync_id, sub_category_sync_id, frequency,
           day_of_month, next_occurrence, active, updated_at, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_id) DO UPDATE SET
          description=excluded.description, amount=excluded.amount, type=excluded.type,
          category_sync_id=excluded.category_sync_id, sub_category_sync_id=excluded.sub_category_sync_id,
          frequency=excluded.frequency, day_of_month=excluded.day_of_month,
          next_occurrence=excluded.next_occurrence, active=excluded.active,
          updated_at=excluded.updated_at, is_deleted=excluded.is_deleted
        WHERE excluded.updated_at > sync_recurring.updated_at
        ''',
        [
          r.syncId, r.description, r.amount, r.type.index, categorySyncId, subCategorySyncId,
          r.frequency.index, r.dayOfMonth, _epoch(r.nextOccurrence), _boolToInt(r.active),
          _epoch(r.updatedAt), _boolToInt(r.isDeleted),
        ],
      ));
    }
    if (processed.isEmpty) return;
    await _client!.execute(statements);
    await _writeWatermark(
      'push_recurring',
      processed.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullRecurring() async {
    final since = await _readWatermark('pull_recurring');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT sync_id, description, amount, type, category_sync_id, sub_category_sync_id, '
        'frequency, day_of_month, next_occurrence, active, updated_at, is_deleted '
        'FROM sync_recurring WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final syncId = row['sync_id'] as String;
      final updatedAt = _fromEpoch(row['updated_at']);

      final categoryId = await _categoryIdFor(row['category_sync_id'] as String?);
      // V. commento in _pullSubCategories: non avanzare la filigrana oltre
      // una riga il cui genitore non è ancora risolvibile.
      if (categoryId == null) continue;
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;
      final subCategoryId = await _subCategoryIdFor(row['sub_category_sync_id'] as String?);

      final existing = await (_db.select(_db.recurringTransactions)
            ..where((r) => r.syncId.equals(syncId)))
          .getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      final companion = RecurringTransactionsCompanion(
        description: Value(row['description'] as String),
        amount: Value((row['amount'] as num).toDouble()),
        type: Value(TransactionKind.values[row['type'] as int]),
        categoryId: Value(categoryId),
        subCategoryId: Value(subCategoryId),
        frequency: Value(RecurringFrequency.values[row['frequency'] as int]),
        dayOfMonth: Value(row['day_of_month'] as int?),
        nextOccurrence: Value(_fromEpoch(row['next_occurrence'])),
        active: Value(_intToBool(row['active'])),
        updatedAt: Value(updatedAt),
        isDeleted: Value(_intToBool(row['is_deleted'])),
        syncId: Value(syncId),
      );
      if (existing == null) {
        await _db.into(_db.recurringTransactions).insert(companion);
      } else {
        await (_db.update(_db.recurringTransactions)..where((r) => r.id.equals(existing.id)))
            .write(companion);
      }
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_recurring', maxUpdatedAt);
  }

  // --- Transactions ---

  Future<void> _pushTransactions() async {
    final since = await _readWatermark('push_transactions');
    final rows = await (_db.select(_db.transactions)
          ..where((t) => t.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1)))))
        .get();
    final dirty = rows.where((r) => r.syncId != null).toList();
    if (dirty.isEmpty) return;

    final statements = <TursoStatement>[];
    // V. commento in _pushSubCategories: la filigrana avanza solo sulle righe
    // effettivamente processate, non su tutte le candidate.
    final processed = <Transaction>[];
    for (final r in dirty) {
      final categorySyncId = await _categorySyncId(r.categoryId);
      if (categorySyncId == null) continue;
      processed.add(r);
      final subCategorySyncId = await _subCategorySyncId(r.subCategoryId);
      final recurringSyncId = await _recurringSyncId(r.recurringId);
      final refundOfSyncId = await _transactionSyncId(r.refundOfId);
      statements.add(TursoStatement(
        '''
        INSERT INTO sync_transactions
          (sync_id, date, amount, type, category_sync_id, sub_category_sync_id, note,
           is_extraordinary, is_refund, recurring_sync_id, refund_of_sync_id, updated_at, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_id) DO UPDATE SET
          date=excluded.date, amount=excluded.amount, type=excluded.type,
          category_sync_id=excluded.category_sync_id, sub_category_sync_id=excluded.sub_category_sync_id,
          note=excluded.note, is_extraordinary=excluded.is_extraordinary, is_refund=excluded.is_refund,
          recurring_sync_id=excluded.recurring_sync_id, refund_of_sync_id=excluded.refund_of_sync_id,
          updated_at=excluded.updated_at, is_deleted=excluded.is_deleted
        WHERE excluded.updated_at > sync_transactions.updated_at
        ''',
        [
          r.syncId, _epoch(r.date), r.amount, r.type.index, categorySyncId, subCategorySyncId,
          r.note, _boolToInt(r.isExtraordinary), _boolToInt(r.isRefund), recurringSyncId,
          refundOfSyncId, _epoch(r.updatedAt), _boolToInt(r.isDeleted),
        ],
      ));
    }
    if (processed.isEmpty) return;
    await _client!.execute(statements);
    await _writeWatermark(
      'push_transactions',
      processed.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullTransactions() async {
    final since = await _readWatermark('pull_transactions');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT sync_id, date, amount, type, category_sync_id, sub_category_sync_id, note, '
        'is_extraordinary, is_refund, recurring_sync_id, refund_of_sync_id, updated_at, is_deleted '
        'FROM sync_transactions WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final syncId = row['sync_id'] as String;
      final updatedAt = _fromEpoch(row['updated_at']);

      final categoryId = await _categoryIdFor(row['category_sync_id'] as String?);
      // V. commento in _pullSubCategories: non avanzare la filigrana oltre
      // una riga il cui genitore non è ancora risolvibile.
      if (categoryId == null) continue;
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;
      final subCategoryId = await _subCategoryIdFor(row['sub_category_sync_id'] as String?);
      final recurringId = await _recurringIdFor(row['recurring_sync_id'] as String?);
      // NOTA: se il rimborso e la spesa originale arrivano nello stesso pull
      // e la spesa non è ancora presente localmente, refundOfId resta null
      // per questo giro (si risolve al sync successivo, quando la spesa
      // originale sarà già stata inserita) — caso raro, non gestito con un
      // secondo passaggio per non complicare il motore di sync.
      final refundOfId = await _transactionIdFor(row['refund_of_sync_id'] as String?);

      final existing =
          await (_db.select(_db.transactions)..where((t) => t.syncId.equals(syncId))).getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      final companion = TransactionsCompanion(
        date: Value(_fromEpoch(row['date'])),
        amount: Value((row['amount'] as num).toDouble()),
        type: Value(TransactionKind.values[row['type'] as int]),
        categoryId: Value(categoryId),
        subCategoryId: Value(subCategoryId),
        note: Value(row['note'] as String?),
        isExtraordinary: Value(_intToBool(row['is_extraordinary'])),
        isRefund: Value(_intToBool(row['is_refund'])),
        recurringId: Value(recurringId),
        refundOfId: Value(refundOfId),
        updatedAt: Value(updatedAt),
        isDeleted: Value(_intToBool(row['is_deleted'])),
        syncId: Value(syncId),
      );
      if (existing == null) {
        await _db.into(_db.transactions).insert(companion);
      } else {
        await (_db.update(_db.transactions)..where((t) => t.id.equals(existing.id))).write(companion);
      }
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_transactions', maxUpdatedAt);
  }

  // --- Impostazioni sincronizzate (whitelist esplicita) ---

  /// Solo queste chiavi della tabella Settings viaggiano su Turso: l'ordine
  /// drag&drop di categorie/sottocategorie resta volutamente locale (è una
  /// preferenza di UI, non un dato), le chiavi `sync_*` sono filigrane interne
  /// di questo stesso motore di sync e non vanno mai toccate da qui.
  static const _syncedSettingsKeys = [savingsGoalSettingsKey];

  Future<void> _pushAppSettings() async {
    final since = await _readWatermark('push_app_settings');
    final dirty = <Setting>[];
    for (final key in _syncedSettingsKeys) {
      final row = await (_db.select(_db.settings)
            ..where((s) =>
                s.key.equals(key) &
                s.updatedAt.isBiggerOrEqualValue(since.add(const Duration(milliseconds: 1)))))
          .getSingleOrNull();
      if (row != null) dirty.add(row);
    }
    if (dirty.isEmpty) return;

    await _client!.execute([
      for (final r in dirty)
        TursoStatement(
          '''
          INSERT INTO sync_app_settings (key, value, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            value=excluded.value, updated_at=excluded.updated_at
          WHERE excluded.updated_at > sync_app_settings.updated_at
          ''',
          [r.key, r.value, _epoch(r.updatedAt)],
        ),
    ]);
    await _writeWatermark(
      'push_app_settings',
      dirty.map((r) => r.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  Future<void> _pullAppSettings() async {
    final since = await _readWatermark('pull_app_settings');
    final result = await _client!.execute([
      TursoStatement(
        'SELECT key, value, updated_at FROM sync_app_settings WHERE updated_at > ?',
        [_epoch(since)],
      ),
    ]);
    DateTime? maxUpdatedAt;
    for (final row in result.first.asMaps()) {
      final key = row['key'] as String;
      if (!_syncedSettingsKeys.contains(key)) continue; // difesa extra oltre al push
      final updatedAt = _fromEpoch(row['updated_at']);
      if (maxUpdatedAt == null || updatedAt.isAfter(maxUpdatedAt)) maxUpdatedAt = updatedAt;

      final existing =
          await (_db.select(_db.settings)..where((s) => s.key.equals(key))).getSingleOrNull();
      if (existing != null && !updatedAt.isAfter(existing.updatedAt)) continue;

      await _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: key,
              value: row['value'] as String,
              updatedAt: Value(updatedAt),
            ),
          );
    }
    if (maxUpdatedAt != null) await _writeWatermark('pull_app_settings', maxUpdatedAt);
  }
}
