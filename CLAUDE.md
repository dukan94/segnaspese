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

- Repo GitHub: https://github.com/dukan94/segnaspese
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
`flutter_secure_storage` (credenziali) · `intl`/`uuid`/`collection`.

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
- Test di regressione: `test/app_database_migration_test.dart` — crea un DB
  v7 completo, riporta `user_version` a 6 lasciando le colonne fisicamente
  presenti (stesso stato di una migrazione interrotta), poi riapre e verifica
  che non lanci eccezioni e che `user_version` torni a 7.
- Se in futuro un'app desktop Windows sembra "non aprirsi" senza errori
  visibili: non fidarsi di `Get-Process`/`Responding=True` da solo (il
  processo nativo può essere vivo col messaggio loop attivo pur con
  l'isolate Dart morto) — controllare se la finestra ha davvero un titolo
  (`MainWindowTitle` vuoto = nessun frame mai renderizzato) e, se serve
  diagnosticare, rilanciare con `flutter run -d windows --release` invece
  dell'exe per vedere lo stack trace reale.

## Sync (Turso) — dettaglio critico

Si usa l'**API HTTP di Turso** (Hrana-over-HTTP, endpoint `/v2/pipeline`) col
pacchetto `http` puro Dart (`data/services/turso_http_client.dart`), **non** il
client nativo `libsql_dart`/embedded replica: quello richiederebbe una
toolchain Rust/cargo per compilare a ogni build, non disponibile su questa
macchina. Non reintrodurre `libsql_dart`.

- Offline-first: si scrive sempre in locale; la sync gira in background, alla
  chiusura, al ritorno in foreground e su richiesta manuale.
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
- Tabella `Merchants`: schema pronto (`syncId`) ma nessun DAO/flusso UI ancora
  collegato — non ha ancora dati.
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
  lavoro futuro separato, non ancora progettato).
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

## CI — build Android APK, quota storage Artifacts

`.github/workflows/android-build.yml` builda un APK **debug** a ogni push su
`main` e lo carica come artifact scaricabile (v. commento nel file per il
perché del keystore committato). Lo storage Artifacts di GitHub Actions sul
piano gratuito è **0.5GB totali per il repo**, condiviso con eventuali altri
workflow — si satura in fretta se gli artifact restano con la retention di
default (90 giorni).

- **Bug reale (5 ago 2026)**: build fallita in fase `actions/upload-artifact`
  con `Artifact storage quota has been hit`. Il job Flutter (`flutter build
  apk --debug`) era andato a buon fine: il fallimento è solo storage, non
  codice — non cercare la causa in un cambiamento di schema/provider/CI se
  l'errore nei log è questo.
- **Retention già abbassata** a `retention-days: 3` (commit `27df76e`) per
  evitare che si riaccumuli, ma questo vale solo per gli artifact **futuri**:
  non libera subito quelli già esistenti, e GitHub ricalcola l'uso storage
  ogni 6-12 ore (non istantaneo dopo una cancellazione manuale). Se una run
  fallisce con questo errore appena dopo aver cancellato gli artifact vecchi
  a mano, non è un segno che la cancellazione non ha funzionato: va solo
  aspettato il ricalcolo prima di rilanciare.
- Se l'errore si ripresenta nonostante `retention-days: 3`: cancellare a
  mano gli artifact vecchi dalla tab Actions del repo (o "Manage artifacts"
  nella singola run), aspettare il ricalcolo, poi rilanciare.

## Stato attuale (16 ago 2026)

Sviluppo per **milestone incrementali** con **design approvato prima di
scrivere codice**, ora messo per iscritto in modo strutturato invece che solo
concordato a voce (v. "Processo per nuove modifiche" più sotto).

- **M0–M24 completate** (tutte le proposte emerse dall'audit best-practice
  del 16 ago 2026 sviluppate — v. `progettazione_finance_app.md` sezione
  6 per il dettaglio completo). M0-M8:
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
  dedupe/client HTTP Turso (M23), **aggiornamento dipendenze — csv,
  flutter_secure_storage, file_picker, go_router, Drift+sqlite3 3.x senza
  più sqlite3_flutter_libs (M24)**. **CI attiva** — `.github/workflows/
  ci.yml`: `flutter analyze` + `flutter test`
  su ogni push/PR con rigenerazione del codice.
- Test in `test/` (24 file, 159 test): parser CSV, receipt parser, rule
  matcher, duplicate finder, sync Turso (incluso **rientranza syncNow()**,
  verifica remota puntuale e migrazione schema remoto), repair
  sottocategorie orfane, widget animati, DAO ricorrenze/categorie/budget/
  transazioni (date-math, riordino, upsert, filtri ricerca, hard
  delete/purge, unione categorie/sottocategorie, numero di occorrenze
  finito), formatter e servizio Google Sheets (header matching),
  SafeTransactionDeletionService (con `FakeTursoHttpClient` + test double
  ufficiale di `FlutterSecureStorage`), parser estratto conto BancoPosta e
  duplicate matcher (fixture xlsx sintetiche), migrazione locale
  idempotente (`app_database_migration_test.dart`, M17), servizio
  Gemini incluso il regression test di sicurezza M18
  (`gemini_vision_service_test.dart`), seed runner
  (`seed_runner_test.dart`), dedupe tassonomia
  (`dedupe_default_taxonomy_test.dart`), client HTTP Turso con
  encoding/decoding reale — non solo `FakeTursoHttpClient`
  (`turso_http_client_test.dart`) — tutti e 4 aggiunti in M23, **export CSV
  (`transaction_export_service_test.dart`, M24 — non esisteva prima
  dell'upgrade di `csv`)** + 1 smoke
  widget test.

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
