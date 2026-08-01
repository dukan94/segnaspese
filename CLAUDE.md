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
  `finance_app.sqlite.backup-2026-08-02-pre-category-merge`. **Resta un
  gap noto**: creare a mano una categoria con lo stesso nome di una già
  esistente non è impedito né segnalato dalla UI (`categories_manage_page.
  dart`) — può succedere di nuovo.

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
  progetto. Icona app e splash screen Android/Windows finalizzati (v.
  sezione dedicata sopra): non più il placeholder di Flutter.

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
