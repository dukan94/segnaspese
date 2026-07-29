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
multi-dispositivo via API HTTP) · `csv`+`file_picker` (import/export) ·
`googleapis`/`googleapis_auth` (bridge temporaneo Google Sheets, v. sotto) ·
`flutter_secure_storage` (credenziali) · `intl`/`uuid`/`collection`.

SDK Dart `>=3.4.0 <4.0.0`. Versione app `0.1.0`. Schema DB Drift: **v6**.

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
- Conflict resolution: **last-write-wins** su `updatedAt` (nessuna protezione
  clock-skew, accettato per uso personale).
- Ogni push/pull di tabella è isolato: un errore su una tabella non blocca le
  altre. Banner di avviso in Home se la sync non è configurata o è in errore.
- Tabella `Merchants`: schema pronto (`syncId`) ma nessun DAO/flusso UI ancora
  collegato — non ha ancora dati.

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

## Stato attuale (lug 2026)

Sviluppo per **milestone incrementali** con **design approvato prima di
scrivere codice** (metodo di lavoro concordato con Mario: mantienilo).

- **M0–M8 completate**: setup + Clean Architecture, core transazioni,
  categorie/budget, scontrini (Gemini + fallback OCR), dashboard, ricorrenti,
  ricerca/import-export CSV, sync Turso + build desktop/Android, rifinitura
  (fix bug critici sync, audit best-practice, dedupe tassonomia post-sync,
  empty states + animazioni leggere, tema unificato sul colore dell'icona,
  rename utente a "Tally", **CI attiva** — `.github/workflows/ci.yml`:
  `flutter analyze` + `flutter test` su ogni push/PR con rigenerazione del
  codice — copertura test estesa al motore di sync e ai DAO con logica reale).
- Test in `test/` (16 file): parser CSV, receipt parser, rule matcher,
  duplicate finder, sync Turso (incluso **rientranza syncNow()** e verifica
  remota puntuale), repair sottocategorie orfane, widget animati, DAO
  ricorrenze/categorie/budget/transazioni (date-math, riordino, upsert,
  filtri ricerca, hard delete/purge), formatter e servizio Google Sheets
  (header matching), **SafeTransactionDeletionService** (con
  `FakeTursoHttpClient` + test double ufficiale di `FlutterSecureStorage`)
  + 1 smoke widget test.
- **Post-M8**: Admin (Impostazioni > Admin) con import CSV spostato lì,
  bridge temporaneo verso il foglio Google "Copia di Spese" e strumenti di
  eliminazione definitiva/pulizia (v. sezione dedicata sopra) — non è una
  milestone, sono strumenti interni, il bridge Sheets va rimosso a fine
  progetto.

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

1. Prima di modifiche non banali proponi il **design** e attendi l'ok.
2. Verifica lo stato reale sul codice (specie milestone e test) prima di
   affidarti a questi documenti.
3. Dopo modifiche a schema Drift o provider: rilancia `build_runner`, poi
   `flutter analyze` e `flutter test`.
4. **Dopo ogni cambiamento** (feature, fix, refactor, milestone che avanza),
   aggiorna subito `README.md` e questo file (e `progettazione_finance_app.md`
   se cambia design/schema) — senza aspettare che venga richiesto
   esplicitamente. Obiettivo: chi apre una nuova sessione (umano o AI) deve
   trovare qui lo stato vero, non doverlo ricostruire da `git log`.
