# CLAUDE.md — Istruzioni per sessioni AI

> File di onboarding rapido per l'assistente AI. Leggilo per intero prima di
> lavorare sul progetto. Documenti di dettaglio: `README.md` (descrizione
> utente) e `progettazione_finance_app.md` (design completo, schema DB,
> milestone). In caso di conflitto, **vince il codice**: verifica sempre sul
> sorgente prima di dare per scontato lo stato.

## Cos'è

**Tally** — app di finanza personale multipiattaforma (Flutter) per uso
privato. Scansiona lo scontrino, ne estrae negozio/importo/data con AI, lo
categorizza e lo salva in un DB locale, con dashboard, budget, movimenti
ricorrenti e sync tra dispositivi. Gira su **Android** e come **app desktop
Windows**, da un'unica base di codice.

- Repo GitHub: https://github.com/dukan94/segnaspese — **pubblico** (reso
  tale il 2 set 2026 per usare GitHub Pages gratuitamente, v. sezione
  "Avviso in-app di aggiornamento" sotto; era privato da sempre prima).
  Nessun segreto committato (verificato prima del cambio): credenziali
  Turso/Gemini/Google Sheets solo in `flutter_secure_storage`, mai nel
  codice.
- Vincolo fondante: **solo strumenti e librerie gratuite**.
- App a utente singolo (Mario), non multi-tenant.

## Stack

Flutter/Dart · **Drift** (SQLite locale, codice generato) · **Riverpod**
(state + DI) · **go_router** · **Material 3** (tema chiaro/scuro) ·
**fl_chart** (grafici) · **Google Gemini** (lettura scontrini via cloud, key
personale) con fallback **Google ML Kit** OCR offline · **Turso** (sync cloud
multi-dispositivo via API HTTP) · `csv`+`excel`+`file_picker` (import/export,
`excel` per gli estratti conto bancari in xlsx, v. sotto) ·
`googleapis`/`googleapis_auth` (bridge temporaneo Google Sheets, v. sotto) ·
`flutter_secure_storage` (credenziali) · `url_launcher` (apre il link di
download del banner di aggiornamento, M47) · `intl`/`uuid`/`collection`.

SDK Dart `>=3.4.0 <4.0.0`. Versione app `0.1.0`. Schema DB Drift: **v7**.

## Architettura — Clean Architecture a 3 livelli

```
presentation/  → UI, pages, widgets, provider Riverpod (dipende solo da domain)
domain/        → entities, repository interfaces, usecases, services (puro Dart)
data/          → Drift DAO/tabelle, repository impl, mapper, servizi (Turso, Gemini)
core/          → di/ (provider globali), theme/, router/, utils/
```

Regole da rispettare quando modifichi il codice:

- Il **domain non conosce Drift né Flutter**: solo entità e interfacce astratte.
- I repository concreti (in `data/repositories_impl/`) convertono le righe
  Drift in entità di dominio tramite i **mapper** (`data/mappers/`).
- Ogni feature è un **modulo verticale** sotto `presentation/` (home, dashboard,
  budget, recurring, history, receipt, transaction, settings, altro).
- Gli errori risalgono come **eccezioni** fino alla UI, che li mostra via
  snackbar (`core/utils/app_snackbar.dart`). Non esistono tipi `Result`/`Failure`.
- La DI è fatta con i **provider Riverpod** (in `core/di/`), niente get_it.

## Comandi

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # rigenera *.g.dart (Drift + Riverpod)
flutter analyze
flutter test
flutter run                 # Android (device/emulatore)
flutter run -d windows      # desktop Windows (richiede VS2022 + workload C++)
```

**Importante:** ogni modifica a tabelle/DAO Drift o ai provider Riverpod
richiede di rilanciare `build_runner`, altrimenti `analyze`/`test` falliscono
su codice generato disallineato. I file `*.g.dart` sono generati: non
modificarli a mano.

**`flutter analyze` fallisce (exit code 1) su QUALSIASI issue, anche solo
`info`** (es. `prefer_const_constructors`), non solo su `error`/`warning` —
la CI (`.github/workflows/ci.yml`) tratta quindi un `info` come un fallimento
a tutti gli effetti. Bug reale (5 ago 2026): un nuovo file di test con 17
`info` di questo tipo è stato scambiato per "innocuo" perché nell'output non
comparivano `error`, senza controllare l'exit code — la CI è comunque
fallita. Dopo `flutter analyze`, controllare sempre l'exit code (`echo $?`
o equivalente), non fermarsi a leggere se compaiono `error` nell'output.

## Stream Drift che dipendono da un'altra tabella (insidia)

`Stream.watch()` di Drift invalida in base alle SOLE tabelle referenziate
dalla query originale. Se dentro un `.asyncMap()` fai una lettura separata su
un'altra tabella (es. `CategoryDao` che legge l'ordine manuale da `Settings`
dentro il calcolo di `watchByType`/`watchSubCategories`/
`watchSubCategoriesForType`), uno stream così **non si accorge se cambia
solo quell'altra tabella** — resta fermo alla vecchia istantanea finché non
cambia qualcosa nella tabella "vera" della query (o l'app non riparte).

Bug reale (29 lug 2026): riordinare categorie/sottocategorie in Impostazioni
scriveva solo su `Settings`, quindi il menù a tendina di "Nuova Operazione"
(altro stream, stessa tabella Settings) non si aggiornava finché l'utente
non riavviava l'app. Fix in `category_dao.dart`: `_combineLatest2` (stream
di supporto locale al DAO) combina lo stream della query principale con uno
stream sull'intera tabella `Settings`, così un cambiamento in una delle due
fa ricalcolare il risultato. Se aggiungi un nuovo stream Drift che legge da
una tabella diversa da quella osservata, usa lo stesso pattern (o assicurati
che la query stessa tocchi quella tabella) invece di un `asyncMap` con una
lettura "silenziosa".

## SQLite nativo — niente più `sqlite3_flutter_libs` (M24)

Dal pacchetto `sqlite3` versione 3.x in poi, i binari nativi SQLite per
Windows/Android vengono scaricati/bundlati automaticamente dai **build hook
di Dart** (`native_toolchain_c`, nessuna dipendenza `sqlite3_flutter_libs`
né configurazione manuale necessaria per l'uso senza cifratura di questo
progetto). `sqlite3_flutter_libs` è stato rimosso dal pubspec (M24, 16 ago
2026): il pacchetto era stato deliberatamente svuotato dall'autore dalla
versione `0.6.0+eol` in poi, proprio per segnalare che non serve più da
quando Drift ≥2.32 supporta `sqlite3` 3.x. **Non reintrodurre
`sqlite3_flutter_libs`** nel pubspec: sarebbe ridondante col nuovo
meccanismo e potenzialmente in conflitto con esso. Nessun `open.overrideFor`
manuale nel codice (mai stato necessario in questo progetto neanche prima).
Verificato con build Windows reale pulita contro il database vero (backup
preventivo prima), `PRAGMA integrity_check` → `ok` con la nuova libreria.

## Migrazioni schema locale (Drift) — insidia

`AppDatabase.migration.onUpgrade` (`app_database.dart`) applica gli `addColumn`/
ALTER TABLE di ogni versione di schema in sequenza (`if (from < N)`). Se il
processo viene ucciso a metà di questa migrazione — un `Stop-Process`/Task
Manager su un'istanza bloccata, o due istanze avviate per errore sullo stesso
file — SQLite può lasciare una ALTER TABLE già applicata fisicamente **senza**
che Drift abbia ancora scritto la nuova versione dello schema (`PRAGMA
user_version`). Al riavvio successivo Drift rilancia `onUpgrade` dalla
versione vecchia, ritenta lo stesso `addColumn` su una colonna che esiste
già → `SqliteException("duplicate column name")`.

- **Bug reale, non solo teorico (16 ago 2026)**: l'eccezione viene lanciata
  in `main()` **prima** di `runApp()` (durante `runSeed`, che apre il DB).
  Un'eccezione non gestita lì non fa "crashare" l'app in modo visibile: il
  runner Windows mostra la finestra solo al primo frame Flutter renderizzato
  (`flutter_window.cpp`, `SetNextFrameCallback`), che non arriva mai se
  l'isolate Dart muore prima. Il processo resta "Responding: True" (il
  message loop nativo C++ continua a girare) ma **nessuna finestra compare**
  — sembra che l'app "non si apra", non che sia crashata. Diagnosticato
  lanciando `flutter run -d windows --release` invece dell'exe compilato
  (l'unico modo per vedere lo stack trace reale su un'app GUI Windows senza
  console). Causa root sul dispositivo di Mario: un'istanza precedente
  bloccata (avviata come amministratore) terminata a forza da Task Manager
  aveva lasciato `recurring_transactions` con le colonne v7
  (`total_occurrences`/`occurrences_generated`) già presenti ma
  `user_version` fermo a 6. Fix una tantum sul file reale (backup prima:
  `finance_app.sqlite.backup-2026-08-16-pre-userversion-fix`): verificato che
  le colonne v7 fossero già coerenti con lo schema atteso, poi
  `PRAGMA user_version = 7` senza toccare righe/dati.
- **Fix strutturale**: ogni `addColumn`/ALTER TABLE in `onUpgrade` (v2→v7) è
  ora avvolto in un controllo `_columnExists(tabella, colonna)` (query
  `PRAGMA table_info`) — idempotente, stesso principio già in uso per lo
  schema remoto Turso (`_addColumnIfMissing` in `turso_sync_service.dart`,
  v. sezione dedicata sotto). Una migrazione interrotta a metà, su questo o
  qualunque altro dispositivo, non blocca più l'avvio.
- **Causa "due istanze" chiusa alla radice su Windows (M38, 18 ago 2026)**:
  `windows/runner/main.cpp` crea un mutex Win32 nominato prima di
  inizializzare Flutter — se esiste già (un'altra istanza è in esecuzione),
  la nuova non apre nulla: porta in primo piano la finestra già aperta
  (`FindWindowW` su classe **e** titolo insieme, per non confondersi con
  un'altra app Flutter Windows eventualmente in esecuzione) ed esce subito.
  Non serve più affidarsi solo alla disciplina di non lanciare l'app due
  volte. Su Android questo non serve: il sistema operativo già impedisce
  nativamente due istanze della stessa app.
- Test di regressione: `test/app_database_migration_test.dart` — crea un DB
  completo, riporta `user_version` a 6 lasciando le colonne fisicamente
  presenti (stesso stato di una migrazione interrotta), poi riapre e verifica
  che non lanci eccezioni e che `user_version` torni a quello corrente (8 —
  era 7 quando questo test è stato scritto per il bug M17, aggiornato con
  lo schema bump di M35 sotto, lo scenario/la guardia testata non cambiano).
- Se in futuro un'app desktop Windows sembra "non aprirsi" senza errori
  visibili: non fidarsi di `Get-Process`/`Responding=True` da solo (il
  processo nativo può essere vivo col messaggio loop attivo pur con
  l'isolate Dart morto) — controllare se la finestra ha davvero un titolo
  (`MainWindowTitle` vuoto = nessun frame mai renderizzato) e, se serve
  diagnosticare, rilanciare con `flutter run -d windows --release` invece
  dell'exe per vedere lo stack trace reale.
- **Eliminare una colonna/tabella (M35, 17 ago 2026)**: `addColumn`
  (sopra) non basta se serve invece **rimuovere** qualcosa. Un
  `ALTER TABLE ... DROP COLUMN` diretto fallisce se la colonna è soggetta
  a un vincolo FOREIGN KEY (SQLite lo rifiuta) — serve
  `Migrator.alterTable(TableMigration(tabella))`, che ricrea la tabella
  secondo la definizione Dart **corrente** (già senza quella colonna)
  copiando le righe esistenti per nome colonna. Per una tabella intera,
  `m.deleteTable('nome_tabella')`. Idempotenza sullo stesso principio di
  `_columnExists`: nuovo `_tableExists(tabella)` (query `sqlite_master`),
  entrambi gli step in `onUpgrade` controllano prima di agire (una
  migrazione interrotta a metà non deve ritentare un `deleteTable` su una
  tabella già sparita). Caso reale: rimozione della tabella `Merchants` e
  della colonna `merchantId` da `Transactions` (v. sezione dedicata sotto
  e `progettazione_finance_app.md` M35) — `merchantId` referenziava
  `Merchants.id`, da qui la necessità di `TableMigration` invece di un
  `DROP COLUMN` semplice.

## Rimozione tabella Merchants (M35)

*(17 ago 2026)* Tabella `Merchants` (pensata per un futuro campo "Negozio"
con autocompletamento, categoria di default per negozio, stat "Top negozi"
in Dashboard) **mai collegata a un DAO/repository/UI/sync in circa un anno
di sviluppo** — sempre 0 righe. Il flusso scontrini reale (M3) ha preso
un'altra strada: nome negozio come testo libero in Nota, categorizzato da
**Regole Merchant** (regex), mai toccando questa tabella. Valutata con
Mario l'implementazione completa vs la rimozione (dopo una domanda aperta
"cosa manca?"): costo (nuovo DAO/repository/mapper, campo "Negozio",
collegamento anche a scontrini/import estratto conto, supporto sync
nuovo, nessun backfill sensato per lo storico) non giustificato dal
beneficio — Regole Merchant + ricerca full-text su Nota già coprono
categorizzazione e ricerca. Scelta: **rimozione** (schema v8), non
abbandono silenzioso.

- Rimossi `merchants_table.dart`, `merchantId` da `Transactions`/
  `TransactionEntity`/`transaction_mapper.dart`/`add_transaction_page.dart`.
  Rimosso anche `merchantQuery` (parametro mai realmente passato da
  nessun chiamante su `TransactionRepository.search`/
  `SearchTransactionsParams` — stesso piano abbandonato).
- **Se serve reintrodurre un concetto di "negozio ricordato"**: non
  riesumare questa tabella senza un piano concreto per collegarla anche a
  scontrini/import estratto conto (altrimenti si ripete lo stesso
  problema — dati sempre vuoti) e per il supporto sync (mai stato
  presente, da costruire da zero: `sync_merchants`, push/pull, traduzione
  FK, stesso principio delle altre tabelle sincronizzate sopra).
- **Verificato anche sul database vero di Mario** (backup preventivo
  `finance_app.sqlite.backup-2026-08-17-pre-m35-merchants-removal`):
  migrazione applicata prima su una copia (0 righe in `merchants`, 0
  transazioni con `merchantId` valorizzato — coerente con l'indagine),
  poi sul file vero via build Windows reale: 1908 transazioni invariate,
  colonna/tabella sparite, `PRAGMA integrity_check` → `ok`.

## Sync (Turso) — dettaglio critico

Si usa l'**API HTTP di Turso** (Hrana-over-HTTP, endpoint `/v2/pipeline`) col
pacchetto `http` puro Dart (`data/services/turso_http_client.dart`), **non** il
client nativo `libsql_dart`/embedded replica: quello richiederebbe una
toolchain Rust/cargo per compilare a ogni build, non disponibile su questa
macchina. Non reintrodurre `libsql_dart`.

- Offline-first: si scrive sempre in locale; la sync gira in background, alla
  chiusura, al ritorno in foreground, ogni 5 minuti, su richiesta manuale e
  (M32, 17 ago 2026) **subito dopo ogni inserimento/modifica/cancellazione
  di una transazione** (`addTransactionProvider`/`updateTransactionProvider`/
  `deleteTransactionProvider` in `core/di/transaction_providers.dart`,
  `unawaited(syncService.syncNow().catchError(...))` — stesso pattern
  fire-and-forget del resto, nessun blocco della UI, nessun errore mostrato
  all'utente). Fuori da questo trigger: l'import CSV bulk (Admin) e le
  transazioni generate dalle ricorrenze all'avvio, che chiamano
  repository/DAO direttamente — stesso perimetro già escluso dal bridge
  Google Sheets sotto.
- Ogni tabella sincronizzata ha campi `updatedAt`, `isDeleted` (soft delete) e
  `syncId` (UUID stabile tra dispositivi). Le FK intere locali diventano
  colonne testuali `*_sync_id` lato remoto.
- **Insidia**: `_ensureRemoteSchema()` (`turso_sync_service.dart`) crea le
  tabelle remote con `CREATE TABLE IF NOT EXISTS`, che **non altera** una
  tabella remota già esistente. Aggiungere una colonna a una tabella locale
  già sincronizzata (bug reale, 3 ago 2026: `totalOccurrences`/
  `occurrencesGenerated` su `RecurringTransactions` per le ricorrenze a
  numero finito) non basta a farla arrivare sul remoto — su un database
  Turso già in uso da prima, `sync_recurring` restava con lo schema vecchio
  e push/pull su quella tabella fallivano con "no such column" per
  chiunque avesse già sincronizzato almeno una volta. Fix: `_ensureRemoteSchema`
  chiama anche `_addColumnIfMissing(tabella, colonna, definizione)` per ogni
  colonna aggiunta dopo il primo rilascio della sync — legge `PRAGMA
  table_info` e fa `ALTER TABLE ... ADD COLUMN` solo se manca, idempotente
  come le `CREATE TABLE IF NOT EXISTS` sopra. **Se aggiungi una colonna a
  una tabella che ha già un `sync_<tabella>` corrispondente, aggiorna anche
  il testo del `CREATE TABLE` (per le installazioni nuove) E aggiungi una
  chiamata a `_addColumnIfMissing`** (per chi ha già sincronizzato prima
  della modifica) — l'una non sostituisce l'altra. Test di regressione in
  `test/turso_sync_service_test.dart` (gruppo "migrazione schema remoto"),
  che pre-semina uno schema remoto "vecchio" nel `FakeTursoHttpClient` per
  riprodurre il bug prima del fix.
- Conflict resolution: **last-write-wins** su `updatedAt` (nessuna protezione
  clock-skew, accettato per uso personale).
- Ogni push/pull di tabella è isolato: un errore su una tabella non blocca le
  altre. Banner di avviso in Home se la sync non è configurata o è in errore.
- **Storico locale con doppioni preesistenti** (scoperto 31 lug 2026, v.
  memoria `project_transaction_duplicates_pre_sync`): sul dispositivo di
  Mario ~94% delle transazioni (749/796) avevano un duplicato di contenuto
  esatto (stessa data/importo/categoria/nota), probabile storico importato
  indipendentemente su più device prima che la sync esistesse.
  `transaction_duplicate_finder.dart` (`findContentDuplicateTransaction`,
  usata da `_pullTransactions` per riconoscere un movimento arrivato da un
  altro device come lo stesso già presente in locale sotto un `syncId`
  diverso, senza inserirlo una seconda volta) assumeva al massimo 1
  candidato locale: con 2+ candidati già esistenti lanciava un'eccezione
  (`Bad state: Too many elements`) che bloccava il pull di **tutte** le
  transazioni, non solo quelle duplicate (bug reale, non solo teorico —
  occorreva quasi a ogni sync). Due fix in sequenza lo stesso giorno:
  1. Un primo fix faceva tornare `null` con 2+ candidati ambigui (niente più
     crash, ma non riconosceva il duplicato): la riga arrivata dal pull
     veniva comunque inserita come nuova, quindi i gruppi già doppi
     CRESCEVANO a ogni sync tra device invece di restare stabili
     (verificato lo stesso giorno: 374 gruppi tutti da 2 copie → 194 da 2 +
     180 da 3 dopo un solo altro giro di sync).
  2. Fix definitivo (1 ago 2026): con 1 o più candidati locali che
     combaciano su tutti i campi, la riga remota è comunque riconosciuta
     come duplicata — la funzione torna un candidato qualsiasi (non importa
     quale: sono identici per contenuto, nessuno dei due viene toccato) solo
     per segnalare "già rappresentato in locale, non inserire". Con 0
     candidati resta `null` (davvero nuovo, va inserito). Questo è il
     comportamento voluto: *se un dispositivo ha già sincronizzato queste
     transazioni prima, quello stato va rispettato*, non ridiscusso a ogni
     pull.
  **Pulizia del backlog già eseguita** (1 ago 2026, script una tantum via
  `AppDatabase.forTesting` puntato sul DB reale, poi rimosso, non
  committato): tenuta 1 riga per gruppo (id più basso; nessuna aveva una
  foto scontrino collegata, quindi la scelta non perde dati), soft-delete
  sulle altre 554 righe, poi sync per propagare. Verificato: 0 gruppi
  duplicati residui tra le transazioni attive dopo la pulizia. Backup del
  file `.sqlite` pre-pulizia lasciato accanto all'originale
  (`finance_app.sqlite.backup-2026-08-01-pre-dedupe`) per sicurezza — v.
  memoria `project_transaction_duplicates_pre_sync` per il dettaglio
  completo.
- **Doppioni categoria default vs personalizzata** (scoperto 2 ago 2026, v.
  memoria `project_category_default_vs_custom_duplicates`): `dedupe_default_
  taxonomy.dart` (gira a ogni avvio) fonde solo doppioni TRA categorie con
  `isDefault = true` — di proposito ignora quelle personalizzate, per non
  toccare a sorpresa dati creati a mano dall'utente. Questo lascia scoperto
  un caso reale: Mario aveva ricreato a mano `Casa`/`Salute`/`Viaggio`
  (nomi identici ai default seedati dall'app, ma sottocategorie diverse,
  allineate al suo storico CSV/Google Sheet) pensando che eliminare gli
  originali li facesse sparire — invece restavano attivi (`isDeleted =
  false`), coesistendo come alberi paralleli con transazioni vere sparse su
  entrambi. Non è un bug di regressione del fix dei doppioni transazioni:
  è un caso strutturalmente diverso (default vs personalizzata, non
  default vs default), che quel meccanismo non copre e non dovrebbe coprire
  in automatico (richiede una mappatura sottocategoria per sottocategoria
  decisa da un umano, non deducibile in sicurezza dal solo nome). Pulizia
  una tantum eseguita lo stesso giorno (stesso metodo: script via
  `AppDatabase.forTesting` sul DB reale, poi rimosso, non committato):
  transazioni/regole merchant delle 3 categorie di default ripuntate sulle
  equivalenti personalizzate (mappatura per nome dove identico, altrimenti
  confermata da Mario), poi le 3 categorie/sottocategorie di default
  soft-deleted. Verificato: 0 doppioni residui, nessuna transazione persa
  (420 attive invariate). Backup pre-pulizia:
  `finance_app.sqlite.backup-2026-08-02-pre-category-merge`.

  **Gap chiuso (2 ago 2026)**, con due fix nella stessa sessione invece di
  un'altra pulizia manuale se il problema si ripresentasse:
  1. `categories_manage_page.dart` ora blocca in UI la creazione/rinomina di
     una categoria o sottocategoria con un nome già esistente (confronto
     case-insensitive, spazi ai bordi ignorati; per le categorie tra quelle
     dello stesso tipo Uscite/Entrate, per le sottocategorie tra quelle
     della stessa categoria padre) — errore inline sul campo Nome, salvataggio
     bloccato finché il nome non cambia.
  2. Per i doppioni che si creano comunque (es. un dispositivo non ancora
     aggiornato, o un caso default-vs-personalizzata come questo), una nuova
     azione **"Unisci con..."** (icona `Icons.merge_type`, accanto a
     modifica/elimina) in Categorie e sottocategorie sposta transazioni,
     regole merchant, budget e ricorrenze dalla categoria/sottocategoria
     sorgente a quella scelta come destinazione — tutto in un'unica
     transazione Drift, `updatedAt` aggiornato su ogni riga toccata per la
     ripropagazione in sync — poi elimina (soft delete) la sorgente. Risolve
     lo stesso caso di questa pulizia (e Salute/Viaggio) dall'app, senza
     script una tantum sul DB reale.
     - **Sottocategoria**: la destinazione può appartenere a una categoria
       padre diversa (serve esattamente per il caso Salute sopra: sposta sia
       `categoryId` sia `subCategoryId`).
     - **Categoria**: rifiutata (eccezione, non silenziosa) se la sorgente ha
       ancora sottocategorie attive con transazioni/regole/ricorrenze
       collegate — vanno prima unite o eliminate quelle (stesso ordine di
       operazioni già seguito a mano per Casa/Salute/Viaggio). Sottocategorie
       attive ma senza dati non bloccano: la cascata di eliminazione già
       esistente (`softDeleteCategory`) le elimina comunque.
     - Dialog di conferma con il conteggio di quante righe verrebbero
       spostate prima di procedere.
     - Codice: `CategoryDao.mergeCategoryInto`/`mergeSubCategoryInto` +
       `categoryHasBlockingSubCategories`/`categoryMergeImpact`/
       `subCategoryMergeImpact` (`data/local/database/daos/category_dao.dart`,
       tabelle aggiunte al `@DriftAccessor`: Transactions, MerchantRules,
       Budgets, RecurringTransactions), usecase `MergeCategory`/
       `MergeSubCategory` (`domain/usecases/category/`), entità
       `CategoryMergeImpact` (`domain/entities/category_entity.dart`). Test
       in `test/category_dao_test.dart`.
     - **Verificato manualmente end-to-end da Mario (2 ago 2026)**, oltre ai
       test automatici: creata una coppia categoria/sottocategoria di prova
       con una transazione collegata, sincronizzata sui due dispositivi
       (PC + telefono), unita la sottocategoria (verso una sottocategoria
       di un'altra categoria padre) e poi la categoria ormai vuota, poi
       eliminate entrambe — ogni passaggio si è propagato correttamente
       sull'altro dispositivo alla sync successiva, nessun errore, nessun
       doppione. Nota emersa durante il test, non un bug: una categoria
       senza sottocategorie non compare mai nel picker di "Nuova Operazione"
       (che sceglie solo la sottocategoria, mai la categoria da sola) —
       comportamento esistente indipendente da questa feature.

## Ricorrenze — numero di occorrenze finito

Oltre alle ricorrenze a tempo indeterminato (comportamento originale), da
schema v7 `RecurringTransactions` ha due colonne opzionali:
`totalOccurrences` (null = indeterminato, come prima) e
`occurrencesGenerated` (contatore, parte da 0). Nel form
(`recurring_edit_page.dart`) un campo "Numero di occorrenze (opzionale)"
imposta `totalOccurrences`; se lasciato vuoto la ricorrenza si comporta
come sempre.

- `RecurringDao.generateDue` si ferma da sola non appena
  `occurrencesGenerated` raggiunge `totalOccurrences` — anche se stava
  recuperando più occorrenze arretrate insieme (app rimasta chiusa a
  lungo): niente sforamento del tetto impostato. Al raggiungimento, imposta
  `active = false`, riusando lo switch "Attiva/Pausa" già esistente invece
  di un nuovo stato — se non lo facesse, la riga resterebbe "attiva" per
  sempre pur non generando più nulla (nessun indizio in UI del perché si è
  fermata).
- **Validazione** (`recurring_edit_page.dart`, stesso stile del controllo
  nomi duplicati delle categorie): abbassare il numero sotto le occorrenze
  già generate è bloccato con errore inline sul campo, non silenzioso.
- **Nessuna riattivazione automatica**: se alzi il tetto su una ricorrenza
  già esaurita (messa in pausa da sola), resta in pausa finché non la
  riattivi tu manualmente con lo switch — scelta deliberata per non far
  cambiare stato allo switch senza un'azione diretta dell'utente.
- Lista (`recurring_list_page.dart`): se `totalOccurrences` è impostato,
  mostra "occorrenza N/M" al posto della sola data prossima occorrenza.
- Sync Turso: due colonne aggiunte a `sync_recurring`
  (`total_occurrences`, `occurrences_generated`), stesso pattern di
  push/pull delle altre colonne (`turso_sync_service.dart`). **Bug reale
  scoperto da Mario appena rilasciato** (3 ago 2026): sul suo database
  Turso già in uso, `sync_recurring` esisteva da prima e non prendeva le
  due colonne nuove solo aggiornando il testo del `CREATE TABLE`
  — push/pull fallivano con "no such column". V. voce dedicata in "Sync
  (Turso) — dettaglio critico" per il fix (`_addColumnIfMissing`) e per la
  regola generale da seguire per ogni futura colonna aggiunta a una
  tabella già sincronizzata.
- Test in `test/recurring_dao_test.dart` (gruppo "numero di occorrenze
  finito"): comportamento indeterminato invariato senza il campo, stop
  esatto al tetto, recupero arretrati che non sfora il tetto, ripresa dopo
  aver alzato il tetto e riattivato a mano.

## Import estratto conto bancario

Feature utente vera (non un tool interno come l'import CSV di Admin), voce
propria in Impostazioni (`presentation/statement_import/
statement_import_page.dart`, route `/settings/statement-import`). Un parser
per banca, aggiunto il 5 ago 2026 partendo da Poste Italiane (BancoPosta),
che esporta xlsx da "Lista movimenti" nell'home banking.

- **Un parser per banca**: interfaccia `domain/services/
  bank_statement_parser.dart` (`BankStatementParser.parse(bytes) →
  List<ParsedStatementRow>`), pura Dart, nessuna dipendenza da Drift/Flutter
  — stesso principio di `CsvTransactionParser`. Aggiungere una nuova banca
  significa implementare l'interfaccia e aggiungerla alla lista in
  `core/di/statement_import_providers.dart` (`bankStatementParsersProvider`),
  senza toccare UI/dedup/categorizzazione. Prima implementazione:
  `bancoposta_statement_parser.dart`.
- **Formato BancoPosta** (osservato sul file reale del 5 ago 2026): righe
  iniziali vuote in numero variabile (spazio per il logo), poi intestazione
  con le colonne `Data Contabile | Data Valuta | Addebiti (euro) | Accrediti
  (euro) | Descrizione operazioni`, poi i movimenti senza un footer da
  scartare. Il parser cerca la riga con "Data Contabile" invece di assumere
  un numero fisso di righe vuote, e si ferma alla prima riga senza data o
  senza addebito/accredito valorizzato (fine dati). Le date sono seriali
  Excel con stile numerico data (`numFmtId` 14): il pacchetto `excel` le
  decodifica già come `DateCellValue`; c'è comunque un fallback che
  interpreta un seriale grezzo (giorni dal 30/12/1899) per file dove la
  cella non porta uno stile data esplicito.
  - **Data Valuta, non Data Contabile** (bug reale, segnalato da Mario 16
    ago 2026): la colonna 0 (Data Contabile) serve SOLO ad ancorare la
    riga di intestazione — la data della transazione va letta dalla
    colonna 1 (Data Valuta), molto più vicina al giorno reale della spesa.
    Il bug era passato inosservato ai test perché tutte le fixture
    usavano la stessa data in entrambe le colonne: se aggiungi un test
    per questo parser, usa sempre date diverse nelle due colonne per non
    perdere la capacità di distinguerle.
- **Arrotondamento importi**: alcuni valori arrivano dal file come double con
  errore di rappresentazione binaria (es. `40.799999999999997` invece di
  `40.8`, osservato nel file reale) — il parser arrotonda sempre a 2
  decimali. Lo stesso vale per il confronto doppioni sotto: mai `==` diretto
  su double letti da Excel.
- **Categorizzazione**: nessun motore nuovo, riuso diretto di
  `RuleMatcherService` sulla causale/descrizione grezza (stesse regole usate
  per gli scontrini) — funziona bene anche senza estrarre il nome
  commerciante dal testo (es. "PAGAMENTO POS IPER MONZA...") perché il
  matching è già una regex su tutto il testo. Righe senza match restano
  "da assegnare": l'utente sceglie la sottocategoria riga per riga in
  revisione (`SubCategoryPicker`, lo stesso widget di "Nuova Operazione");
  una riga inclusa ma senza sottocategoria non blocca le altre, semplicemente
  non viene importata (conteggio "incluse senza categoria" mostrato a parte).
- **Modifica riga per riga** (aggiunto lo stesso giorno, richiesto da Mario
  dopo la prima verifica: scegliere solo la categoria non bastava, a volte
  serve correggere data/importo/tipo/nota della riga letta dal file):
  l'icona matita su ogni riga apre `AddTransactionPage` (la stessa schermata
  di "Nuova Operazione"/modifica storico) in modalità "bozza" — nuovi
  parametri `draftDate`/`draftAmount`/`draftType`/`draftNote`/
  `draftSelection` + `onDraftSaved` sul widget esistente. A differenza della
  modifica di una transazione già salvata (`existing`), qui `onDraftSaved`
  intercetta il salvataggio: niente scrittura sul database, l'operazione
  compilata torna alla riga di revisione (che aggiorna i suoi campi
  modificabili) e l'import vero resta rimandato alla conferma finale in
  fondo alla lista. Salta anche il controllo doppioni di
  `AddTransactionPage` (già coperto dal badge della riga). Verificato a
  runtime: editing di importo/tipo/data/nota/categoria di una riga BONIFICO,
  round-trip corretto (contatori "incluse senza categoria"/"Importa N
  operazioni" aggiornati subito dopo il salvataggio della bozza).
- **Doppioni — tolleranza diversa dalla sync**: `domain/services/
  statement_duplicate_matcher.dart` (`StatementDuplicateMatcher`) è
  volutamente più permissivo di `transaction_duplicate_finder.dart` (quello
  usato dalla sync Turso, match esatto su tutti i campi). Qui una
  transazione già inserita a mano ha quasi certamente nota/categoria diverse
  da quelle dedotte dall'estratto conto: l'unico segnale affidabile è
  **importo uguale (arrotondato al centesimo) + tipo uguale + data entro
  ±3 giorni** (di default) dalla data contabile, che spesso non coincide col
  giorno reale della spesa (v. `PAGAMENTO POS` nel formato BancoPosta, dove
  la data reale è nella descrizione). Le righe segnalate sono escluse di
  default dalla selezione ma restano modificabili, mai bloccate del tutto:
  la decisione finale resta a chi importa.
- **Dati reali di test**: `ListaMovimenti.xlsx` nella root del repo (export
  vero di Mario, dati finanziari reali) è in `.gitignore` — non versionarlo
  mai. I test (`test/bancoposta_statement_parser_test.dart`,
  `test/statement_duplicate_matcher_test.dart`) usano fixture xlsx
  sintetiche costruite a runtime col pacchetto `excel` stesso (dati finti
  che ricalcano la struttura reale), mai il file vero.

## Icona app e splash screen

Sorgente in `assets/icon/`: `tally_icon.png` (carrello ambra/arancio con "T",
sfondo crema pieno — stessi colori del tema, v. `_brandSeedColor`/
`_brandCream` in `app_theme.dart`) e `tally_icon_foreground.png` (solo
carrello+T, sfondo trasparente). Generate con `flutter_launcher_icons` e
`flutter_native_splash` (dev dependency, config in fondo a `pubspec.yaml`),
non a mano.

Per rigenerare dopo aver cambiato i PNG sorgente:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
powershell -File tool/generate_windows_icon.ps1
```

**Il terzo comando non è opzionale.** `flutter_launcher_icons` per Windows
scrive `windows/runner/resources/app_icon.ico` con una sola risoluzione
(256, da `icon_size` in pubspec.yaml): nitido a piena dimensione ma sfocato
quando Windows lo scala per taskbar/Alt-Tab/finestra. Lo script ricostruisce
lo stesso file con 7 risoluzioni (16–256) dalla stessa sorgente PNG. Se
rilanci solo `flutter_launcher_icons` senza lo script dopo, il file torna
a una sola risoluzione senza errori visibili: da controllare se l'icona in
taskbar sembra sfocata.

Android usa icona adattiva (API 26+, `mipmap-anydpi-v26/ic_launcher.xml`,
sfondo colore `#FAF0E0` + foreground trasparente) più fallback legacy per
API più vecchie; splash screen nativo sia pre-Android 12 (`launch_background.
xml`) sia Android 12+ (`windowSplashScreenBackground`/
`windowSplashScreenAnimatedIcon` in `values-v31/styles.xml`), stesso schema
crema/arancione.

**`flutter build apk --release` ora funziona** (fix 1 ago 2026): falliva per
un problema R8 preesistente e scollegato dall'icona/splash, scoperto mentre
si indagava sul crash della sync — R8 vedeva riferimenti a classi ML Kit dei
riconoscitori testo per altri alfabeti (cinese/giapponese/coreano/
devanagari, mai usati: l'app legge solo scontrini in italiano/latino) e
falliva senza una regola che lo rassicurasse. Fix in
`android/app/proguard-rules.pro` (righe `-dontwarn` per quelle 8 classi,
collegato al build type release in `android/app/build.gradle.kts` via
`proguardFiles`). Release è anche molto più leggero del debug (~95MB contro
~200MB, minificazione/shrink attivi solo in release).
`.github/workflows/android-build.yml` continua comunque a buildare
**debug** (scelta esplicita di Mario, 1 ago 2026, non riproporre il cambio
senza nuovo contesto): il fix resta disponibile per quando/se servirà una
build release.

## Admin (strumenti interni)

Impostazioni > **Admin** (`presentation/settings/admin_page.dart`, fuori dal
flusso normale di Impostazioni, nessuna password) raccoglie strumenti interni:

- **Import CSV** (spostato qui da Impostazioni, v. `import_page.dart`): solo
  sviluppo/backfill, non il vero import da estratto conto bancario (quello è
  in Impostazioni, v. sezione dedicata "Import estratto conto bancario"
  sopra — implementato in M15, questa nota era rimasta non aggiornata).
- **Backup completo con un click (M43)**: `DatabaseBackupService`
  (`data/services/database_backup_service.dart`) copia il file `.sqlite`
  locale grezzo (nessuna cifratura/trasformazione) tramite
  `FilePicker.saveFile()`, stesso meccanismo dell'export CSV — sostituisce
  gli script Dart usa-e-getta fatti a mano prima di ogni operazione
  rischiosa (v. i vari `finance_app.sqlite.backup-...` citati in questo
  file). Sicuro senza precauzioni aggiuntive perché il database **non usa
  WAL** (`app_database.dart`, `_openConnection`) — nessun file `-wal`/
  `-shm` da doversi preoccupare di includere nella copia. Percorso del
  file condiviso con `_openConnection` tramite `resolveDatabaseFile()`
  (`app_database.dart`), un solo punto invece di duplicare la logica.
- **Bridge Google Sheets** verso il foglio "Copia di Spese" già usato a mano:
  finché attivo, ogni transazione salvata tramite `addTransactionProvider`
  (non l'import CSV, che resta un bulk tool separato) viene copiata in
  background anche lì, stesso schema colonne (`data/services/
  google_sheets_row_formatter.dart`, ricalca `spese.csv`). **Temporaneo**:
  da disattivare col relativo switch quando l'app sarà completa e testata al
  100% — non va esteso oltre questo scopo.
  - Autenticazione **service account** (`google_sheets_service.dart`), non
    OAuth interattivo: `google_sign_in` non supporta Windows desktop, e
    l'app gira da un'unica codebase su Windows+Android. Setup (fuori
    dall'app, a cura di Mario): service account su Google Cloud, foglio
    condiviso con la sua email come Editor.
  - Fallimenti di rete/permessi qui sono isolati e non bloccano/non fanno
    fallire il salvataggio locale (stesso principio della sync Turso).
  - Copre solo `addTransactionProvider` (inserimento manuale/da scontrino):
    **non** copre le transazioni generate dalle ricorrenze (`RecurringDao.
    generateDue` inserisce direttamente via DAO), né modifiche o
    cancellazioni fatte dopo il salvataggio. Il foglio può divergere
    dall'app in quei casi (comunicato in UI).
  - `testConnection` verifica anche che l'intestazione reale del tab
    combaci con `GoogleSheetsService.expectedHeader` (stesso ordine di
    `GoogleSheetsRowFormatter`), non solo che il tab esista — altrimenti le
    righe finirebbero silenziosamente nelle colonne sbagliate.
- **Gestione transazioni** (`data/services/safe_transaction_deletion_service.dart`):
  il DB fa di norma solo soft delete (serve a propagare le cancellazioni in
  sync). Da Admin si può eliminare per sempre (irreversibile): una
  transazione scelta cercandola (nota/categoria/importo/data), o in blocco
  tutte quelle già soft-deleted ("Pulisci database"). Solo tabella
  `Transactions` per ora (non categorie/budget/ricorrenze).
  - **`SafeTransactionDeletionService` è l'UNICO punto d'accesso.**
    `TransactionDao.hardDelete`/`getSoftDeletedIds` sono primitive di basso
    livello: non chiamarle direttamente da un usecase o dalla UI. Non esiste
    più (rimosso di proposito) un `hardDelete`/`purgeSoftDeleted` su
    `TransactionRepository` — esporli lì inviterebbe a bypassare la verifica.
  - **Non basta che `syncNow()` non lanci eccezioni.** Prima di ogni hard
    delete/purge, il servizio fa un tentativo di sync (best-effort, fino a 3
    volte) e poi legge DIRETTAMENTE dal server (`TursoSyncService.
    isTransactionDeletionConfirmedRemotely`) se quella riga risulta
    davvero cancellata — solo a conferma ottenuta elimina fisicamente.
    Copre in un colpo solo: righe scartate in silenzio dal push (FK non
    ancora sincronizzata), upsert LWW che non aggiorna nulla (clock skew,
    pareggio di `updatedAt`), e sync di sfondo sovrapposte. Se non
    confermata, la transazione resta soft-deleted (nascosta, non persa) e
    va ritentata più tardi da "Pulisci database".
  - **`TursoSyncService.syncNow()` non ha più una guardia di rientranza
    "silenziosa".** Prima (fino al 29 lug 2026) una chiamata concorrente
    ritornava subito senza eccezione se una sync era già in corso, senza
    garanzia che avesse davvero spinto le modifiche più recenti. Ora aspetta
    quella in corso e ne lancia comunque una fresca (mai si accontenta di un
    giro iniziato prima della propria chiamata) — importante con più
    dispositivi attivi, dove le sync di sfondo si sovrappongono spesso. Non
    reintrodurre `if (_syncing) return;`.
  - `_destructiveOpInProgress` in `admin_page.dart` disabilita tutti i
    pulsanti distruttivi mentre uno è in corso: cortesia UI, non la vera
    garanzia di sicurezza (quella è la verifica sul server sopra).
  - Righe mai sincronizzate (nessun `syncId`, o mai arrivate sul server) si
    considerano sempre sicure da eliminare: nessuna copia remota da cui
    potrebbero "ricomparire".
  - L'hard delete rimuove comunque il "tombstone" locale una volta
    confermato: se il secondo dispositivo con lo storico non ancora
    risincronizzato (v. memoria `project_second_device_pending`) reinserisse
    la stessa transazione DOPO quel punto, non c'è modo di riconoscerla come
    duplicata — irrilevante finché quel dispositivo resta non risincronizzato.

## CI — build Android/Windows, quota storage/minuti Artifacts

`.github/workflows/android-build.yml` builda un APK **debug** (v. commento
nel file per il perché del keystore committato) e `windows-build.yml`
builda la release desktop Windows (M46, parte Windows, 2 set 2026) —
entrambi pubblicano/sostituiscono l'asset su una release GitHub fissa
(`android-latest`/`windows-latest`, v. sezioni Admin/Distribuzione Windows
sopra), **non** più come Artifact scaricabile della run. Entrambi **solo su
richiesta manuale** (`workflow_dispatch`, tab Actions > "Build Android
APK"/"Build Windows App" > "Run workflow"), mai su push (v. bug reale
sotto, 17 ago 2026). `ci.yml` (`flutter analyze` + `flutter test`) resta
invece automatico ad ogni push/PR: è il vero controllo qualità, e costa
molto meno in minuti.

- **`windows-build.yml` costa 2x sul conteggio minuti** (runner
  `windows-latest`, contro 1x di `ubuntu-latest`): stima 16-24 minuti di
  quota per pubblicazione (8-12 min di build reale × 2). Precauzioni
  aggiunte apposta nel riprendere questa milestone (richiesta esplicita di
  Mario, 2 set 2026, dopo i ripetuti incidenti di quota di agosto):
  **trigger solo manuale** (Mario decide quando serve davvero una build
  aggiornata, non un automatismo su ogni push) e una **cache dei pacchetti
  pub** (`actions/cache` su `%LOCALAPPDATA%\Pub\Cache`, chiave su hash di
  `pubspec.lock`) per accorciare le run successive alla prima quando le
  dipendenze non cambiano — l'SDK Flutter stesso è già cachato da
  `subosito/flutter-action` (`cache: true`). **Non ancora verificato con
  una run reale**: solo sintassi YAML validata offline. Concordato con
  Mario un solo run di verifica quando pronto, non ripetuto a piacere,
  proprio per contenere il consumo reale finché non si conosce il tempo
  effettivo di una build su questo runner.
- **Audit pre-verifica (2 set 2026)**, richiesto esplicitamente da Mario
  prima del run di verifica reale sopra: skill `code-review` sui commit di
  M46-Windows + M47, 5 findings risolti prima di ogni lancio reale — il
  più rilevante, la cache pub packages di `windows-build.yml` era un
  no-op silenzioso (`${{ env.LOCALAPPDATA }}` non esiste nel contesto
  `env` delle espressioni GitHub Actions, che espone solo variabili
  dichiarate in un blocco `env:` del workflow, non quelle reali del
  runner — fix: `PUB_CACHE` dichiarato esplicitamente come `env:` del
  job). Più: `version.json` poteva regredire a un numero più basso con
  run duplicate ravvicinate (fix: `max` invece di assegnazione diretta,
  in entrambi i workflow), race CDN tra i due job `publish-version`
  mitigata con cache-busting sull'URL, `AndroidManifest.xml` privo della
  query di package-visibility per `url_launcher` (Android 11+), banner
  M47 senza gestione errori su `launchUrl` (v. dettaglio completo in
  `progettazione_finance_app.md` M46). `flutter analyze` pulito, 221/221
  test invariati.

- **Bug reale (5 ago 2026)**: build fallita in fase `actions/upload-artifact`
  con `Artifact storage quota has been hit`. Il job Flutter (`flutter build
  apk --debug`) era andato a buon fine: il fallimento è solo storage, non
  codice — non cercare la causa in un cambiamento di schema/provider/CI se
  l'errore nei log è questo. Storage Artifacts sul piano gratuito: **0.5GB
  totali per il repo**, condiviso con eventuali altri workflow.
  - Retention abbassata a `retention-days: 3` (commit `27df76e`) per
    evitare che si riaccumuli, ma vale solo per gli artifact **futuri**: non
    libera subito quelli già esistenti, e GitHub ricalcola l'uso storage
    ogni 6-12 ore (non istantaneo dopo una cancellazione manuale). Se una
    run fallisce con questo errore appena dopo aver cancellato gli artifact
    vecchi a mano, non è un segno che la cancellazione non ha funzionato:
    va solo aspettato il ricalcolo prima di rilanciare.
  - Se l'errore si ripresenta nonostante `retention-days: 3`: cancellare a
    mano gli artifact vecchi dalla tab Actions del repo (o "Manage
    artifacts" nella singola run), aspettare il ricalcolo, poi rilanciare.
- **Bug reale, quota minuti (17 ago 2026)**: entrambi i workflow hanno
  iniziato a fallire istantaneamente ("Failed in 2 seconds", nessuno step
  eseguito) su ogni push — non un bug nel codice/YAML: i **2.000 minuti
  Actions/mese gratuiti** dell'account erano esauriti (notifica GitHub
  "100% used", si azzera automaticamente a inizio ciclo successivo). Con
  più push su `main` nella stessa sessione, ogni push faceva scattare
  *due* workflow completi (`ci.yml` + `android-build.yml`, quest'ultimo il
  più costoso: `flutter pub get` + `build_runner` + `flutter build apk` da
  zero ogni volta) — cumulativamente ha esaurito la quota del mese. Fix:
  `android-build.yml` spostato su `workflow_dispatch` (sopra), riducendo il
  consumo automatico al solo `ci.yml`. Se ricompare questo tipo di errore
  ("Failed in 2 seconds" su ogni push, nessuno step eseguito): controllare
  prima la mail/notifica quota minuti Actions di GitHub, non il codice.
- **Bug reale, pagamento fallito (19 ago 2026)**: `ci.yml` (job
  `analyze-and-test`) non parte più nemmeno lui, con un messaggio diverso
  dai due sopra: *"The job was not started because recent account payments
  have failed or your spending limit needs to be increased."* — non è né
  storage Artifacts né minuti mensili esauriti (che si azzerano da soli a
  fine ciclo): è un problema di **pagamento/metodo di fatturazione** o
  **spending limit** sull'account GitHub, che blocca ogni workflow finché
  non risolto a mano. Nessuna causa nel codice/YAML da cercare — verificare
  in GitHub, sezione **Settings > Billing & plans** dell'account (metodo di
  pagamento aggiornato, o alzare lo spending limit), non risolvibile da
  Claude Code. **Verificato lo stesso giorno sulla pagina Billing reale di
  Mario**: metered usage e included usage coincidevano esattamente
  ($12.48 = $12.48, netto $0, nessun importo insoluto, "Next payment due"
  vuoto) — quindi non un pagamento davvero fallito, ma quota gratuita del
  ciclo (1-30 ago) esaurita senza spending limit configurato per
  l'eccedenza: stesso bug di fondo del 17 ago, testo d'errore diverso.
  Risolto da solo al ciclo successivo (31 ago/1 set), nessuna azione
  di pagamento necessaria.
- **Parsimonia minuti, deciso con Mario (19 ago 2026)**: analizzato il
  consumo reale di agosto (92 commit, 35 merge da inizio mese) — la causa
  di fondo non era `android-build.yml` (già `workflow_dispatch`-only dal 17
  ago) ma `ci.yml` stesso: girava su `on: push` **senza filtro di branch**,
  quindi ogni push su un branch di lavoro *e* di nuovo su `main` dopo il
  merge contava come run separata (~125 run stimate da 35 feature/fix).
  **Scartata** l'opzione più aggressiva (`branches: [main]`, che avrebbe
  tagliato il consumo di più): Mario lavora da **due PC in parallelo** e
  vuole sempre poter fare almeno un push di fine giornata anche su un
  branch non ancora mergiato (anche di soli file `.md`) per restare
  sincronizzato tra i due — perdere la verifica CI automatica su quel push
  avrebbe tolto proprio il segnale più utile in quello scenario. Applicate
  invece solo le ottimizzazioni che non toccano frequenza/copertura dei
  push: `paths-ignore: ['**.md']` (un commit di soli `.md` non tocca
  codice Flutter, salta la run senza impedire il push — git e trigger CI
  sono indipendenti), `concurrency` con `cancel-in-progress: true`
  raggruppato per `github.ref` (cancella una run superata da un push
  successivo sullo **stesso** branch, non interferisce tra branch diversi
  lavorati in parallelo dai due PC), rimosso `pull_request:` (mai usate PR
  in questo repo, trigger morto). `on: push` resta senza filtro di branch
  — invariato, per non rompere il caso d'uso sopra.

## Layout desktop-adattivo (M26-M31)

Refactor richiesto da Mario il 16 ago 2026 ("l'app è scomoda da usare da
pc" — elementi troppo da touch, contenuto stirato a piena larghezza).
Ogni pagina toccata da M26 in poi segue lo stesso schema — riusarlo per
coerenza invece di inventarne uno nuovo:

- `isWideWindow(context)` (`core/utils/responsive.dart`, soglia 900dp) per
  decidere Row/griglia (finestra larga) vs Column (sotto la soglia, stesso
  comportamento di sempre — Android non cambia mai).
- `ContentWidthLimiter` (`presentation/shared_widgets/`) per centrare il
  contenuto con una larghezza massima invece di stirarlo edge-to-edge:
  `maxWidth: 640` per pagine a colonna singola tipo form, `960` per pagine
  con griglie/colonne interne (Dashboard, Budget). **Lo spazio guadagnato
  da una finestra larga resta respiro (margini), non diventa contenuto in
  più** — principio esplicito di Mario durante la discussione del mockup
  Home, non va violato aggiungendo widget "perché c'è spazio" (es. niente
  grafici in Home, che non li ha mai avuti).
- Nessuna nuova "famiglia di card" per desktop: le card continuano a usare
  il `CardTheme` globale già esistente (`app_theme.dart`), che garantisce
  raggio/padding coerenti da solo. L'omogeneità va cercata raggruppando
  per **relazione funzionale**, non per "sono entrambi grafici" (es.
  Dashboard: torta sola a sinistra, andamento 12 mesi + barre
  sottocategoria impilate a destra — **revisionato 17 ago 2026**, prima
  era torta+barre a sinistra e andamento a destra, v. M28 in
  `progettazione_finance_app.md` per il dettaglio) o riconoscendo
  **elementi ripetuti e comparabili** (es. Budget:
  12 mesi/N categorie → griglia `GridView` a 4 colonne con `mainAxisExtent`
  fisso, non una lista; un blocco singolo come `AnnualSummaryCard` non
  entra nella griglia, resta a piena larghezza sopra).
- `VisualDensity.adaptivePlatformDensity` (M26, in `app_theme.dart`) è
  invece globale, non per-pagina: non serve ripeterlo.
- Ogni pagina è stata prima discussa con un mockup HTML (non genera
  codice, solo per concordare la direzione) e approvata da Mario prima di
  scrivere il codice Flutter — stesso metodo per ogni futura pagina
  adattata.
- **M31 (Form e Impostazioni, 17 ago 2026)**: qui NON si applica la parte
  su "elementi ripetuti e comparabili → griglia" sopra — proposta una
  griglia per Regole Merchant (stesso pattern di Budget M29), **scartata
  esplicitamente da Mario** dopo aver visto il mockup ("più semplice da
  implementare e comode da usare" con la sola centratura). Tutte le pagine
  rimaste (`add_transaction_page.dart`, `settings_page.dart`,
  `categories_manage_page.dart`, `merchant_rules_page.dart`,
  `export_page.dart`, `import_page.dart`, `sync_page.dart`,
  `gemini_page.dart`, `theme_page.dart`, `admin_page.dart`,
  `statement_import_page.dart`) hanno solo `ContentWidthLimiter` (640
  default, 900 per Admin/Import estratto conto — righe più dense). **Non
  riproporre una griglia per queste pagine** senza una richiesta esplicita
  nuova. Fix incluso: in Storico (M30) la barra di ricerca non era
  centrata come la lista sotto — `ContentWidthLimiter` ora avvolge
  l'intero body, non solo la lista. Aggiunta richiesta a parte: icona "i"
  in AppBar in Regole di classificazione, apre un bottom sheet
  (`showRuleHelpSheet`) che spiega la sintassi del pattern (regex
  case-insensitive cercata ovunque nel testo, priorità, pattern non validi
  ignorati silenziosamente) — v. `rule_matcher_service.dart` per il
  comportamento reale che il testo descrive.

## Storico — card ridisegnata, colori entrata/badge rimborso (M30)

*(17 ago 2026)* A differenza di M26-M29, qui **niente master-detail**:
Mario ha scelto esplicitamente la lista di sempre, solo centrata con
`ContentWidthLimiter(maxWidth: 760)` — stesso principio "lo spazio in più
resta respiro" delle altre pagine, nessun nuovo pattern di navigazione.

- `_HistoryTile` (`history_page.dart`) ridisegnata: icona categoria +
  **data isolata** (`AppFormatters.dayMonth`) nel `leading` (prima la data
  era dentro la stringa `subtitle` unita con "·", ora ha un suo spazio
  dedicato), Nota come `title`, **sottocategoria sotto la Nota** come
  `subtitle` (prima mostrava il nome categoria — l'icona a sinistra già la
  comunica, la sottocategoria è testo più specifico). Importo e icone
  azione a destra invariati. **Aggiornamento (M36, 18 ago 2026)**: su
  schermo stretto (telefono) questo layout basato su `ListTile` risultava
  illeggibile — la card è stata ricostruita su due righe indipendenti, v.
  sezione "Stato attuale" e M36 in `progettazione_finance_app.md`.
- **Sfondo colorato solo per le entrate** (`AppTheme.incomeContainer`/
  `onIncomeContainer` in `app_theme.dart`, stesso principio di
  `warningContainer`: colori fissi indipendenti dal seed, non derivati da
  `ColorScheme.tertiary`). **Un rimborso NON ha uno sfondo dedicato** —
  prima versione mostrata a Mario ne aveva uno (verde acqua/teal), scartato
  dopo revisione: resta identico a una spesa normale.
- **Colori scelti da Mario, non dedotti dal seed dell'app**: entrata chiaro
  `#C9E59D` → scuro `#344913` (stessa tonalità/saturazione HSL, solo più
  scuro — criterio applicato per derivare lo scuro, non scelto a mano da
  Mario). Testo chiaro `#436B06`; testo scuro: **riusa il colore chiaro
  scelto da Mario stesso** (`#C9E59D`) invece di una quarta tonalità
  scollegata, così l'armonia resta la stessa tra i due temi.
- **Badge "spesa già rimborsata"**: cerchietto colorato (non solo icona
  piatta) accanto alla Nota sulle spese con almeno un rimborso collegato
  (`refundOfId` di una o più righe = id di questa spesa — mai assunto un
  solo rimborso, v. M25 "nessun tetto"). Colore fisso scelto da Mario,
  **non differenziato chiaro/scuro** (a differenza dell'entrata sopra: un
  cerchietto piccolo resta leggibile sia su chiaro sia su scuro):
  `AppTheme.refundedBadgeColor` (`#E5E39F`) / `onRefundedBadgeColor`
  (`#6B6806`). Al tap, nuovo `linked_refunds_sheet.dart` (direzione
  opposta di `linked_expense_sheet.dart`, che risale dal rimborso alla
  spesa): mostra tutti i rimborsi collegati a questa spesa, non solo il
  primo.
- **Iterazione sui colori**: prima proposta con sfondo colorato anche per
  il rimborso (verde acqua/teal calcolato, non scelto da Mario) — bocciata
  a schermo. Poi Mario ha fornito lui i due esadecimali chiari (entrata/
  rimborso) da usare — bocciata di nuovo la parte "rimborso", tenuta solo
  l'entrata; il colore rimborso è stato spostato sul badge. **Se si
  ritocca ancora questa palette**: i colori sono solo in
  `app_theme.dart` (un punto solo, per richiesta esplicita di Mario — non
  aggiungere `Color(0x...)` sparsi in `history_page.dart`).

## Distribuzione Windows — GitHub Releases (M37)

*(18 ago 2026)* Prima di questa milestone l'unico modo per aggiornare
l'app Windows su un dispositivo era ricompilarla da sorgente. Ora la build
release (`flutter build windows --release`) viene compressa in zip
(`Compress-Archive`, PowerShell — nessun tool nuovo, la cartella di build
di Flutter è già portabile, non serve un vero installer) e pubblicata come
allegato di un'unica release GitHub "rolling", tag **`windows-latest`**:

```
https://github.com/dukan94/segnaspese/releases/download/windows-latest/Tally-Windows.zip
```

Il link resta fisso nel tempo: aggiornare significa sostituire l'allegato
sulla release esistente mantenendo lo stesso nome file, non crearne una
nuova — stesso principio "sempre l'ultima build, nessuno storico da
mantenere" già usato per l'APK Android (`android-build.yml`).

- **Perché GitHub Releases e non Google Drive** (proposta iniziale di
  Mario): Drive mostra un avviso "impossibile eseguire la scansione
  antivirus" sui file eseguibili/zip che complica il download diretto, e
  non tiene uno storico versioni. Il repo è già su GitHub, nessun servizio
  nuovo da configurare.
- **Perché uno zip e non un installer vero** (scartata l'alternativa Inno
  Setup): zero strumenti nuovi da installare sul PC di build, coerente con
  la scelta fatta più volte in questo progetto di preferire la soluzione
  più semplice che risolve il problema.
- **Pubblicazione**: dipende dal PC. Sul PC di lavoro (aziendale) `gh` CLI
  non è installabile (stesso motivo per cui manca l'Android SDK, v. sezione
  distribuzione Android) — lì Mario pubblica/aggiorna la release dal
  browser. Sul PC personale (27 ago 2026) `gh` CLI è stata installata via
  `winget install --id GitHub.cli` + `gh auth login --web` (autenticato
  come `dukan94`): da lì la pubblicazione è automatizzabile con
  `gh release upload windows-latest Tally-Windows.zip --repo
  dukan94/segnaspese --clobber` dopo build+zip, nessun passaggio da
  browser. `--clobber` sostituisce l'asset esistente mantenendo lo stesso
  nome file/link. **Automatizzato da GitHub Actions (M46, parte Windows, 2
  set 2026)**: `.github/workflows/windows-build.yml`, `workflow_dispatch`
  (mai su push), stesso modello di `android-build.yml` — v. sezione CI
  sotto per il dettaglio e le precauzioni sui minuti.
- V. M37/M46 in `progettazione_finance_app.md` per il dettaglio completo.

## Avviso in-app di aggiornamento disponibile (M47)

*(2 set 2026)* Banner in Home (`_UpdateAvailableBanner`, `home_page.dart`,
stesso posto/stile del banner soglia budget M40) che confronta il numero
di build in esecuzione con quello più recente pubblicato per la stessa
piattaforma, letto da un piccolo `version.json` pubblico su GitHub Pages.

- **Numero di build, non numero di versione**: `pubspec.yaml` resta fermo
  a `0.1.0` da sempre — non affidabile per un confronto automatico.
  `currentBuildNumber` (`core/di/update_providers.dart`) =
  `int.fromEnvironment('BUILD_NUMBER', defaultValue: 0)`, valorizzato solo
  dai workflow CI (`--dart-define=BUILD_NUMBER=${{ github.run_number }}`
  in `android-build.yml`/`windows-build.yml`) — un contatore monotono per
  workflow, mai deciso a mano. **`0` per una build locale/di sviluppo**
  (mai lanciata da CI): `shouldShowUpdateBanner` lo tratta come "nessun
  numero di build reale da confrontare", altrimenti il banner
  comparirebbe ad ogni avvio in sviluppo (qualunque numero pubblicato
  sarebbe "più recente" di 0).
- **`version.json` su GitHub Pages, non nella release**: il repo è
  privato, scaricare da lì via API richiederebbe un token — mai da
  incorporare nell'app (stesso principio guida di M18 sulla API key
  Gemini). **Correzione (2 set 2026)**: l'assunzione iniziale che GitHub
  Pages fosse gratuito anche su repo privato era sbagliata — l'interfaccia
  mostra "Upgrade or make this repository public to enable Pages" sul
  piano Free. Deciso con Mario: **repo reso pubblico** (Settings > Danger
  Zone > Change visibility), invece di pagare un piano a pagamento
  (contro il vincolo fondante "solo strumenti gratuiti") o complicare con
  un Gist + Personal Access Token. Verificato prima nessun segreto
  committato nella storia del repo (credenziali Turso/Gemini/Google Sheets
  sempre solo in `flutter_secure_storage`, mai nel codice) — l'unico file
  "particolare" è il keystore Android di debug (password fissa nota
  `android`/`android`, rischio basso, pratica standard per CI Flutter).
  Pages attivato subito dopo (Settings > Pages > Source: "GitHub Actions").
  Ogni workflow ha un job `publish-version` (`needs: build`, così
  un problema qui non blocca la release già pubblicata nel job
  precedente) che legge il JSON esistente (fallback `{}` se non ancora
  pubblicato), aggiorna solo la propria chiave (`android`/`windows`) con
  `jq`, ripubblica (`actions/upload-pages-artifact` + `actions/
  deploy-pages`). **Entrambi i job girano su `ubuntu-latest`, anche quello
  di `windows-build.yml`**: aggiornare un JSON non ha bisogno del runner
  Windows, farlo lì raddoppierebbe il costo in minuti per nulla — stessa
  cautela sui minuti già applicata al resto di M46. Stesso
  `concurrency.group` (`pages-version-json`) in entrambi i workflow, per
  serializzare l'esecuzione di due deploy quasi contemporanei da Android e
  Windows — non garantisce da sola che il secondo veda già il deploy del
  primo (GitHub Pages è dietro una CDN, un margine di propagazione
  residuo resta possibile anche così), mitigato con cache-busting
  sull'URL (`?_=<run_id>`) e con un aggiornamento sempre "a salire"
  (`max` tra il valore letto e quello nuovo, mai una riscrittura diretta)
  così una run che legge un JSON non ancora aggiornato non fa mai
  regredire il numero già pubblicato — v. "Audit pre-verifica" nella
  sezione CI sopra per il dettaglio di come è stato scoperto.
- **Richiede un'azione manuale una tantum di Mario, non ancora fatta**:
  attivare GitHub Pages (Settings del repo → Pages → Source: "GitHub
  Actions"). Finché non è attivata, i job `publish-version` falliscono
  (la pubblicazione della release resta comunque riuscita, job separato) e
  l'app non troverà mai un `version.json` da leggere — nessun banner,
  nessun errore visibile (v. sotto).
- **Fallimenti isolati, stesso principio di sync/Google Sheets**:
  `UpdateCheckService.fetchLatestBuildNumber` (`data/services/
  update_check_service.dart`) non lancia mai un'eccezione — rete assente,
  Pages non ancora propagato, JSON non valido: sempre e solo `null`,
  niente banner, niente snackbar d'errore.
- **Dismiss per numero di build, non per mese**: a differenza
  dell'avviso soglia budget (M40, dismiss mensile), qui
  `updateBannerDismissedBuildSettingsKey` memorizza lo specifico numero
  di build chiuso — se ne esce una ancora più recente, il banner riappare
  da solo (v. `shouldShowUpdateBanner`).
- **Apertura del link — errori gestiti, non silenziosi**: `_openDownloadLink`
  (`home_page.dart`) avvolge `launchUrl` in try/catch e controlla anche il
  valore di ritorno (`false` = nessuna app trovata, senza lanciare
  un'eccezione) — su fallimento, `showErrorSnackBar`, stessa regola di
  ogni altro punto dell'app. Su Android, `AndroidManifest.xml` ha
  bisogno di una query di package-visibility dedicata per l'intent
  `VIEW`/`https` (Android 11+, qui sempre applicabile: target/compileSdk
  36) oltre a quella già presente per `PROCESS_TEXT` — senza,
  `url_launcher` non trova alcun browser anche se installato (scoperto
  nell'audit pre-verifica, v. sezione CI).
- **Test**: `extractBuildNumberForPlatform` (lettura chiave
  `android`/`windows` da un JSON già decodificato) è una funzione pura
  separata dalla chiamata di rete apposta per essere testabile — non si
  può testare passando da `Platform.isAndroid` reale, perché in
  `flutter test` è sempre `false` (i test girano sull'host, non su un
  dispositivo Android). `flutter analyze` pulito, 221/221 test (209 + 12:
  `test/update_banner_test.dart` + `test/update_check_service_test.dart`).
- **Non ancora verificato con un run reale**: nessuno dei due workflow è
  stato lanciato dopo questa modifica — in attesa dell'attivazione di
  GitHub Pages da parte di Mario e del run di verifica già pianificato
  per M46-Windows (v. sezione CI sopra), da cui si vedrà anche se
  `publish-version`/il banner funzionano davvero end-to-end.

## Stato attuale (2 set 2026)

Sviluppo per **milestone incrementali** con **design approvato prima di
scrivere codice**, ora messo per iscritto in modo strutturato invece che solo
concordato a voce (v. "Processo per nuove modifiche" più sotto).

- **M0–M47 completate** (M47 in codice, ma in attesa dell'attivazione di
  GitHub Pages e di un run di verifica reale, v. sotto) (v.
  `progettazione_finance_app.md` sezione 6 per il dettaglio completo). M0-M8:
  setup + Clean Architecture, core transazioni, categorie/budget, scontrini
  (Gemini + fallback OCR), dashboard, ricorrenti, ricerca/import-export CSV,
  sync Turso + build desktop/Android, rifinitura (fix bug critici sync,
  audit best-practice, dedupe tassonomia post-sync, empty states +
  animazioni leggere, tema unificato sul colore dell'icona, rename utente a
  "Tally", CI attiva). M9-M24 (dettaglio completo, con date e cosa è stato
  fatto davvero, in `progettazione_finance_app.md` sezione 6 — qui solo il
  titolo): Admin e manutenzione dati (M9), icona/splash "Tally" (M10),
  robustezza doppioni transazioni + avviso doppioni manuali (M11), build
  Android release (M12), blocco doppioni categoria + "Unisci con..." (M13),
  ricorrenze a numero di occorrenze finito (M14), import estratto conto
  bancario (M15), rifiniture ricerca/dashboard/CI (M16), migrazione schema
  locale idempotente (M17), fix sicurezza API key Gemini in messaggi
  d'errore (M18), gestione errori su cancellazione transazione
  Home/Storico (M19), verifica tag `+eol` `sqlite3_flutter_libs` (M20),
  timeout su chiamate Google Sheets (M21), isolamento errori nell'avvio,
  `_runStartupStep` in main.dart (M22), copertura test per Gemini/seed/
  dedupe/client HTTP Turso (M23), aggiornamento dipendenze — csv,
  flutter_secure_storage, file_picker, go_router, Drift+sqlite3 3.x senza
  più sqlite3_flutter_libs (M24). Rimborso con divisore (M25). **Refactor
  desktop-adattivo (M26-M29, v. sezione dedicata sopra)**: fondamenta
  (densità, `NavigationRail`, `ContentWidthLimiter`, M26), Home (M27),
  Dashboard (M28), Budget (M29) riorganizzate su finestra larga. **Storico
  (M30, v. sezione dedicata sopra)**: card ridisegnata (data isolata,
  sottocategoria sotto la Nota), sfondo verde per le entrate, badge
  colorato per le spese con rimborso collegato — niente master-detail,
  scelta esplicita di Mario. **Form e Impostazioni adattivi (M31, v.
  sezione dedicata sopra)**: `ContentWidthLimiter` su tutte le pagine
  rimaste, niente griglie (scartate da Mario), icona info nelle Regole di
  classificazione. **Sync immediata su salvataggio (M32, v.
  sezione Sync sopra)**: inserimento/modifica/cancellazione transazione
  lanciano subito una sync in background, oltre al timer ogni 5 minuti
  (invariato). **Conteggio/media Dashboard (M33)**: torta per categoria e
  barre sottocategoria mostrano ora anche quante volte è ricorsa una
  spesa e il suo valore medio, al netto dei rimborsi (badge col numero +
  "media X €") — logica di aggregazione estratta in `buildDashboardData`
  (funzione pura, testabile) da `dashboard_providers.dart`. **Doppio
  click → Storico filtrato (M34)**: doppio click su una riga di legenda
  categoria o su una barra sottocategoria in Dashboard apre lo Storico con
  la ricerca testuale già impostata su quel nome (`HistoryPage.
  initialQuery`, `state.extra` sulla route `/history`) — attenzione se si
  tocca ancora `_LegendRow` in `category_donut.dart`: ha sia `onTap`
  (seleziona la categoria) sia `onDoubleTap` (apre lo Storico) sullo
  stesso `InkWell`, quindi il singolo click lì ha il ritardo standard
  Flutter (~300ms) per disambiguare dal doppio — le barre sottocategoria
  non hanno questo effetto (nessun altro tap con cui competere).
  Dashboard rivista due volte lo stesso giorno su richiesta di Mario:
  colonna sinistra ora solo la torta, colonna destra andamento 12 mesi +
  barre sottocategoria impilate (v. M28 in `progettazione_finance_app.md`
  per il prima/dopo); e tutti gli importi mostrati in Dashboard (più la
  card "Riepilogo annuale" del Budget, `annual_summary_card.dart`, M29)
  arrotondati senza decimali — nuovo `AppFormatters.currencyRounded`/
  `signedCurrencyRounded`, usato **solo** in questi due punti: il resto
  dell'app (Home, Storico, Budget salvo quella card) mostra ancora i
  centesimi, non toccare `AppFormatters.currency` esistente. **Rimozione
  tabella Merchants (M35, v. sezione dedicata sopra)**: mai collegata a
  DAO/UI/sync in un anno, rimossa con schema v8 (`TableMigration`, non un
  `DROP COLUMN` diretto — vincolo FK). **Storico: card a due righe (M36,
  18 ago 2026)**: bug di leggibilità scoperto da Mario aprendo l'app sul
  secondo dispositivo (telefono) — su schermo stretto la sottocategoria
  sotto la Nota (M30) risultava illeggibile/tagliata. Primo tentativo (menu
  "⋮" per rimborsa/rimborso con divisore/elimina al posto di 3
  `IconButton`) non bastava da solo: in un `ListTile`, `trailing` sottrae
  larghezza condivisa sia a `title` sia a `subtitle`, quindi la
  sottocategoria restava comunque schiacciata. Fix vero: `_HistoryTile`
  non è più un `ListTile` ma `Card > InkWell > Column` su due righe
  indipendenti — riga 1 (icona con data sotto invece che accanto, su
  proposta di Mario + Nota+importo+menu "⋮"), riga 2 (sottocategoria/tag,
  larghezza piena, mai condivisa con l'importo). V. M36 in
  `progettazione_finance_app.md` per il dettaglio. **Distribuzione Windows
  via GitHub Releases (M37, v. sezione dedicata sopra)**: build release
  compressa in zip, pubblicata come allegato di un'unica release "rolling"
  (tag `windows-latest`), link di download fisso nel tempo. **Blocco
  seconda istanza su Windows (M38)**: mutex Win32 nativo in
  `windows/runner/main.cpp`, v. sezione "Migrazioni schema locale" sopra
  per il dettaglio — chiude alla radice la causa nota di una migrazione
  interrotta a metà. **Aggiornamento dipendenze rimasto da M24 (M39)**:
  `fl_chart` 0.68→1.2, `google_mlkit_text_recognition` 0.13→0.17,
  `flutter_lints` 4→6 — nessuna modifica al codice necessaria, verificato
  anche a runtime (grafici Dashboard) con build Windows reale. `camera`
  (dipendenza morta) resta apposta fuori da questo giro, da rimuovere a
  parte. **Home: avviso soglia budget (M40)**: banner richiudibile (per il
  mese corrente) quando il budget del mese raggiunge il 90% o è già
  sforato — `shouldShowBudgetAlert` (funzione pura testata) in
  `budget_providers.dart`, `_BudgetThresholdBanner` in `home_page.dart`,
  stato "chiuso" in una chiave Settings locale non sincronizzata.
  **Rimozione `camera` (M41)**: dipendenza morta (mai importata, residuo
  pre-`image_picker` di M3), tolta dal `pubspec.yaml` insieme alle sue 4
  implementazioni per piattaforma mai usate. **Audit completo del codice
  (M42)**: 10 findings da un audit con lo skill `code-review` su `lib/` a
  copertura massima, risolti in ordine di gravità — il più rilevante, un
  rimborso che perdeva il collegamento per sempre se pullato prima della
  sua spesa (`turso_sync_service.dart`, contraddiceva il commento nel
  codice stesso), più altri 3 bug di uguaglianza esatta su double invece
  di arrotondata (stessa classe dell'incidente dei 554 doppioni), un gap
  nel trigger di sync immediata M32 sull'import estratto conto, e
  un'ottimizzazione mirata della cache FK nel motore di sync (solo lato
  push, mai lato pull — v. M42 in `progettazione_finance_app.md` per il
  perché di questa distinzione, importante se si tocca ancora quel file).
  **Admin: backup completo con un click (M43)**: copia grezza del file
  `.sqlite` locale (sicura, il database non usa WAL), salvata dove vuole
  l'utente tramite lo stesso meccanismo `FilePicker.saveFile()` già usato
  dall'export CSV — v. sezione Admin sotto per il dettaglio. **Storico:
  filtri separati per data e importo (M45, 19 ago 2026)**: il campo di
  ricerca testuale resta invariato, aggiunte 2 icone accanto ad esso
  (calendario, €) che aprono rispettivamente un range di date
  (`showDateRangePicker`) e un range di importi (dialog con min/max) —
  combinabili in AND tra loro e col testo, tutto client-side in
  `history_page.dart` come il filtro testuale preesistente. Tocca per
  impostare/modificare, tieni premuto per rimuovere il singolo filtro.
  **Dashboard: formato budget "attuale/budget" (M44, 20 ago 2026)**: la
  card "Budget" in Dashboard (`AnnualTotals`) mostra ora `<attuale> /
  <budget>` invece del solo tetto — speso in grassetto (stesso colore di
  stato verde/rosso/outline di prima), tetto più piccolo e non in
  grassetto dopo "/", nessun "/ ..." se il budget non è impostato.
  **Pubblicazione automatica su release fissa, Android + Windows (M46,
  completata — parte Android 20 ago 2026, parte Windows 2 set 2026)**:
  `android-build.yml`/`windows-build.yml` non caricano più i binari come
  Artifact della run (3 giorni di retention, quota storage 0.5GB) — li
  pubblicano/sostituiscono su release GitHub "rolling" (`gh` CLI, già
  preinstallata sui runner GitHub-hosted, nessun nuovo secret), tag
  `android-latest`/`windows-latest`:
  `https://github.com/dukan94/segnaspese/releases/download/android-latest/Tally-Android.apk`
  e `.../windows-latest/Tally-Windows.zip` — stesso trigger
  `workflow_dispatch` per entrambi (mai su push), stesso build **debug**
  Android di sempre. Parte Windows ripresa dopo il reset quota del 1°
  settembre con precauzioni esplicite di Mario per il costo 2x su
  `windows-latest`: trigger solo manuale + cache pacchetti pub, un solo
  run di verifica pianificato (non ancora eseguito) — v. sezione CI sotto
  per il dettaglio e `progettazione_finance_app.md` M46 per la cronologia
  completa. **Banner in-app "nuova versione disponibile" (M47, 2 set
  2026, v. sezione dedicata sotto)**: `currentBuildNumber` (`--dart-define
  =BUILD_NUMBER`, passato dai due workflow) confrontato con un
  `version.json` pubblicato su GitHub Pages da un nuovo job
  `publish-version` in ciascun workflow — codice completo e testato
  (221/221), **ma non ancora verificato con un run reale**: richiede
  prima che Mario attivi GitHub Pages (Settings del repo → Pages →
  Source: "GitHub Actions"), azione manuale una tantum non ancora fatta.
  **CI attiva** — `.github/workflows/ci.yml`: `flutter
  analyze` + `flutter test` su ogni push/PR con rigenerazione del codice
  (`android-build.yml`/`windows-build.yml` solo su richiesta manuale, v. sezione dedicata
  sotto).
- Test in `test/` (32 file, 221 test): parser CSV, receipt parser, rule
  matcher, duplicate finder, sync Turso (incluso **rientranza syncNow()**,
  verifica remota puntuale e migrazione schema remoto), repair
  sottocategorie orfane, widget animati, DAO ricorrenze/categorie/budget/
  transazioni (date-math, riordino, upsert, filtri ricerca, hard
  delete/purge, unione categorie/sottocategorie, numero di occorrenze
  finito), formatter e servizio Google Sheets (header matching),
  SafeTransactionDeletionService (con `FakeTursoHttpClient` + test double
  ufficiale di `FlutterSecureStorage`), parser estratto conto BancoPosta e
  duplicate matcher (fixture xlsx sintetiche), migrazione locale
  idempotente (`app_database_migration_test.dart`, M17 **+ rimozione
  tabella Merchants M35**), servizio
  Gemini incluso il regression test di sicurezza M18
  (`gemini_vision_service_test.dart`), seed runner
  (`seed_runner_test.dart`), dedupe tassonomia
  (`dedupe_default_taxonomy_test.dart`), client HTTP Turso con
  encoding/decoding reale — non solo `FakeTursoHttpClient`
  (`turso_http_client_test.dart`) — tutti e 4 aggiunti in M23, export CSV
  (`transaction_export_service_test.dart`, M24 — non esisteva prima
  dell'upgrade di `csv`), **rimborso con divisore
  (`build_split_refund_test.dart`, M25)**, conteggio/media Dashboard
  (`dashboard_data_test.dart`, M33 — logica di aggregazione estratta in
  una funzione pura apposta per essere testabile), avviso soglia budget
  (`budget_alert_test.dart`, M40 — stesso principio: logica di soglia
  estratta in `shouldShowBudgetAlert`), arrotondamento importi centralizzato
  (`money_rounding_test.dart`, M42 — unico punto (`roundToCents`) per una
  formula prima duplicata in 3 file), backup completo
  (`database_backup_service_test.dart`, M43 — solo `suggestedFileName`,
  unica vera logica del servizio), avviso aggiornamento disponibile
  (`update_banner_test.dart`/`update_check_service_test.dart`, M47 —
  stesso principio: logica pura estratta in `shouldShowUpdateBanner`/
  `extractBuildNumberForPlatform`) + 1 smoke widget test.

### Processo per nuove modifiche (da qui in avanti)

Deciso con Mario il 16 ago 2026: il lavoro dopo M8 era fatto bene ma poco
visibile, catalogato solo come "Post-M8" informale invece che come milestone
numerate — rendendo più facile perdere il filo su cosa fosse già stato fatto
(v. l'incidente in "Come lavorare su questo progetto" punto 0). Da qui in
avanti **ogni modifica non banale** (nuova feature, estensione a una
milestone esistente, fix strutturale) segue sempre, in ordine: categorizza
(nuova milestone M<N>, estensione di una già chiusa, o solo una nota in
un'"insidia" esistente) → documenta la proposta in
`progettazione_finance_app.md` sezione 6 PRIMA di scrivere codice, stato
🔧 Proposta → attendi l'ok di Mario → sviluppa (analyze/test) → aggiorna la
voce a ✅ Completata con cosa è stato fatto davvero → propaga lo stato a
`README.md` (tabella milestone) e qui sopra. Dettaglio completo del processo
in `progettazione_finance_app.md`, fondo sezione 6.

## Convenzioni

- **Lingua**: UI, commenti e messaggi di commit in **italiano**.
- **Piattaforme generate**: Windows (`windows/`) e Android (`android/`,
  `applicationId` dedicato, permesso INTERNET). Per aggiungerne altre:
  `flutter create --platforms=<piattaforma> .`, poi verificare permessi e
  `minSdk` (≥ 21 per ML Kit/camera). macOS/iOS/Linux non generate.
- **Font importi**: `PublicSans` (OFL) al posto di Aptos Display (proprietario,
  non ridistribuibile). Font variabile, un solo file per tutti i pesi.
- **Lint**: `package:flutter_lints/flutter.yaml` (`analysis_options.yaml`).
- **Segreti** (credenziali Turso, API key Gemini, chiave JSON service account
  Google Sheets): solo in `flutter_secure_storage`, mai committati.

## Come lavorare su questo progetto

0. **Sincronizza SEMPRE per primo, prima di leggere codice o iniziare
   qualunque lavoro**: `git fetch --all` poi allinea `main` locale a
   `origin/main` (fast-forward se il locale non ha commit propri, altrimenti
   fermati e chiedi). Mario lavora in parallelo da **due PC diversi**, ognuno
   con una propria sessione Claude Code: git è lo strumento con cui i due
   ambienti restano sincronizzati, quindi l'esperienza deve essere
   indistinguibile da un unico posto di lavoro. Un locale rimasto indietro
   porta a rifare (o peggio, a duplicare/entrare in conflitto con) lavoro già
   fatto e pushato dall'altra sessione — **successo reale, non solo
   teorico** (16 ago 2026): una sessione ha rifatto da zero un fix per la
   quota storage GitHub Actions già risolto e pushato 11 giorni prima
   dall'altro PC, scoperto solo perché Mario si è ricordato di aver già
   affrontato quel problema. Se emergono branch remoti con lavoro non ancora
   mergiato in `main` durante il fetch, segnalarlo esplicitamente invece di
   ignorarlo.
1. Prima di modifiche non banali: categorizza, documenta la proposta come
   voce di milestone in `progettazione_finance_app.md` sezione 6 (stato
   🔧 Proposta) e attendi l'ok esplicito di Mario prima di scrivere codice —
   v. "Processo per nuove modifiche" più sotto per il dettaglio completo.
2. Verifica lo stato reale sul codice (specie milestone e test) prima di
   affidarti a questi documenti.
3. Dopo modifiche a schema Drift o provider: rilancia `build_runner`, poi
   `flutter analyze` e `flutter test`.
4. **Dopo ogni cambiamento** (feature, fix, refactor, milestone che avanza),
   aggiorna subito `README.md` e questo file (e `progettazione_finance_app.md`
   se cambia design/schema) — senza aspettare che venga richiesto
   esplicitamente. Obiettivo: chi apre una nuova sessione (umano o AI) deve
   trovare qui lo stato vero, non doverlo ricostruire da `git log`.

## Autorizzazioni permanenti (non richiedere di nuovo conferma per queste)

Mario le ha già concesse esplicitamente; valgono per ogni sessione futura,
non solo quella in cui sono state date:

- **Workflow git per fix/feature importanti**: branch dedicato →
  `flutter analyze` + `flutter test` in locale → merge diretto su `main`
  (`--no-ff`) → push di branch e main. **Nessuna Pull Request**, mai (progetto
  personale mono-sviluppatore). Per typo/doc/modifiche cosmetiche a basso
  rischio: commit diretto su `main`, senza branch.
- **Verifica con build reale**: lanciare `flutter build windows --release` e
  avviare l'eseguibile per un controllo a runtime è autorizzato come parte
  normale della verifica, senza chiedere il permesso ogni volta. Se serve
  automatizzare click/screenshot: MAI uno screenshot a schermo intero (rischio
  di catturare altre finestre/dati non tuoi) — solo della finestra dell'app,
  ritagliata al suo rettangolo.
- **Reset locale (Android)**: `android:allowBackup` resta al default (non
  disattivarlo) — deciso esplicitamente il 29 lug 2026, non riproporlo salvo
  nuovo contesto.
- **Pannello Admin senza password**: deciso esplicitamente (v. sezione Admin
  sopra) — non riproporre un gate a password salvo richiesta esplicita.
