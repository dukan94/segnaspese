# Progettazione Completa — App Finanze Personali (Flutter)

> Documento di design originale, mantenuto aggiornato allo stato reale
> dell'implementazione (v. sezione 6 per lo stato milestone e le note a fondo
> pagina). Le nuove milestone/estensioni continuano a seguire il metodo di
> lavoro concordato: design approvato prima di scrivere il codice.

---

## 1. Architettura del Progetto

Clean Architecture a 3 livelli, con dependency injection e repository pattern per garantire testabilità ed estendibilità (es. futura sync cloud).

```
┌─────────────────────────────────────────────┐
│                PRESENTATION                  │
│  Widgets, Pages, Providers/Riverpod, Router  │
│  → dipende solo da Domain (interfacce)       │
└───────────────────┬───────────────────────────┘
                    │ usa
┌───────────────────▼───────────────────────────┐
│                   DOMAIN                       │
│  Entities, UseCases, Repository Interfaces     │
│  → nessuna dipendenza esterna (puro Dart)      │
└───────────────────┬───────────────────────────┘
                    │ implementato da
┌───────────────────▼───────────────────────────┐
│                    DATA                        │
│  Drift DAOs (SQLite locale embedded replica),  │
│  SyncService (Turso libSQL remote), Repository │
│  Impl, OCR service, Excel import/export        │
└─────────────────────────────────────────────────┘
```

### Sync multi-dispositivo (Turso) — **implementata (M7), v. `turso_sync_service.dart`**

Pattern **offline-first**, realizzato così com'è stato effettivamente costruito
(diverso dalla proposta iniziale con embedded replica, v. nota sotto):

- Ogni dispositivo (telefono/PC) mantiene un file **SQLite locale** (letto/scritto da Drift come sempre, nessuna latenza percepita dall'utente).
- `TursoSyncService` sincronizza in modo bidirezionale il file locale con il database remoto su **Turso**, chiamando l'**API HTTP di Turso (Hrana-over-HTTP, endpoint `/v2/pipeline`)** tramite il pacchetto puro Dart `http` (`turso_http_client.dart`) — **non** tramite il client nativo `libsql_dart`/embedded replica ipotizzato in fase di design: avrebbe richiesto una toolchain Rust/cargo per compilare codice nativo a ogni build, non disponibile su questa macchina.
- Ogni tabella locale sincronizzata ha una controparte remota `sync_<tabella>` con schema "sync-friendly": le foreign key intere locali diventano colonne testuali (`*_sync_id`) valorizzate con lo `syncId` (UUID) della riga referenziata.
- L'app resta **pienamente funzionante offline**: scrivi in locale, la sync avviene in background/alla chiusura/al ritorno in primo piano, e su richiesta manuale.
- **Risoluzione conflitti**: last-write-wins basato su `updatedAt`, applicata sia lato server (upsert con `WHERE excluded.updated_at > ...`) sia lato client al pull. Nessuna protezione da clock skew tra dispositivi (accettato per uso personale).
- Ogni passo di push/pull (una tabella) è isolato: un errore su una tabella non blocca le altre né i cicli successivi.
- Un banner in Home avvisa se la sync non è configurata o è in errore persistente (oltre alla sola icona in AppBar).
- Il layer `domain/` non cambia: i repository restano le stesse interfacce astratte già progettate.
- **Costo:** piano Free di Turso, ampiamente sufficiente per i volumi di un'app di finanza personale.
- **Tabella `Merchants`**: ha lo schema pronto (`syncId`) ma nessun DAO/repository/flusso UI collegato — non ha ancora dati da sincronizzare.

**State management:** Riverpod (generatore di codice, gratuito, si integra bene con Drift per gli stream reattivi delle query).

**Dependency Injection:** Riverpod providers stessi fungono da DI container (niente get_it necessario, ma è comunque compatibile in futuro).

**Routing:** go_router (dichiarativo, gratuito, supporta deep link per futura estensione).

### Principi chiave
- Il Domain non conosce Drift né Flutter: solo entità e interfacce astratte (`TransactionRepository`, `CategoryRepository`, ecc.).
- I casi d'uso (`UseCase`) incapsulano la logica di business (es. `ClassifyReceiptUseCase`, `ComputeBudgetBalanceUseCase`).
- I repository concreti in Data convertono i modelli Drift (generati) in entità di dominio tramite mapper.
- Ogni feature (Home, Transazioni, Budget, Ricorrenze, Scanner, Statistiche, Impostazioni) è organizzata come modulo verticale, per facilitare l'estensione.

---

## 2. Struttura delle Cartelle

> Aggiornata allo stato reale del codice (v. anche README.md). Rispetto alla
> proposta iniziale sotto, alcune astrazioni previste non sono mai state
> necessarie in pratica: niente `Failure`/`Result<T>` (gli errori arrivano
> come eccezioni fino alla UI, che li mostra via snackbar), niente
> `merchant_repository`/`import_export_repository` (CSV e Merchant non hanno
> bisogno di un repository dedicato, v. sotto), niente cartella `constants/`
> (icone e regex vivono accanto a chi le usa).

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router + tema
│
├── core/
│   ├── di/                           # provider Riverpod globali: database,
│   │                                  # categorie, budget, ricorrenze, merchant
│   │                                  # rules, sync, settings, tema, Gemini
│   ├── theme/                        # ColorScheme M3 light/dark personalizzabile
│   ├── router/                       # go_router config (app_router.dart)
│   └── utils/                        # formatters (valuta, date), app_snackbar
│
├── domain/
│   ├── entities/                     # transaction, category, merchant_rule,
│   │                                  # budget, recurring (niente Merchant:
│   │                                  # tabella pronta ma non ancora usata)
│   ├── repositories/                  # interfacce astratte: transaction,
│   │                                  # category, merchant_rule, budget, recurring
│   ├── services/                     # receipt_parser_service (OCR+regex),
│   │                                  # rule_matcher_service, csv_transaction_
│   │                                  # parser, transaction_export_service
│   └── usecases/
│       ├── transaction/              # add/update/delete/search
│       ├── category/                 # add/update/delete (categoria+sotto),
│       │                              # reorder
│       ├── budget/                   # set_monthly/set_category/delete
│       ├── merchant_rule/            # add/update/delete
│       └── recurring/                # add/update/delete/set_active/
│                                      # generate_due_recurring
│
├── data/
│   ├── local/
│   │   ├── database/
│   │   │   ├── app_database.dart     # Drift @DriftDatabase (schemaVersion 6)
│   │   │   ├── tables/               # transactions, categories, subcategories,
│   │   │   │                         # merchants, merchant_rules, budgets,
│   │   │   │                         # recurring, settings
│   │   │   └── daos/                 # transaction, category, merchant_rule,
│   │   │                              # budget, recurring
│   │   └── seed/                     # default_categories/subcategories/
│   │                                  # merchant_rules_seed, seed_runner,
│   │                                  # dedupe_default_taxonomy (riparazione
│   │                                  # doppioni post-sync multi-dispositivo)
│   ├── services/
│   │   ├── turso_http_client.dart    # client HTTP puro Dart per l'API Hrana
│   │   ├── turso_sync_service.dart   # push/pull bidirezionale, conflict res.
│   │   ├── sync_service.dart         # interfaccia SyncService + SyncStatus
│   │   ├── gemini_vision_service.dart # lettura scontrino via Google Gemini
│   │   └── gemini_api_key_store.dart # API key Gemini in flutter_secure_storage
│   ├── mappers/                      # Drift row ↔ Domain entity
│   └── repositories_impl/            # transaction, category, merchant_rule,
│                                      # budget, recurring
│
└── presentation/
    ├── home/                          # home_page, home_providers, widgets/
    │                                  # (balance_card, budget_summary_card,
    │                                  # monthly_stats_row, recent_transactions)
    ├── transaction/                   # add_transaction_page (manuale +
    │                                  # modifica + rimborso collegato),
    │                                  # widgets/ (amount_keypad, category_picker)
    ├── receipt/                       # receipt_scan_page (foto/galleria +
    │                                  # Gemini/OCR su mobile, testo su desktop)
    ├── dashboard/                     # dashboard_page/providers, widgets/
    │                                  # (monthly_trend_chart, category_donut,
    │                                  # subcategory_bars, annual_totals)
    ├── budget/                        # budget_page, budget_month_page,
    │                                  # budget_providers, widgets/
    ├── recurring/                     # recurring_list_page, recurring_edit_page
    ├── history/                       # history_page (ricerca full-text +
    │                                  # elenco movimenti)
    ├── altro/                         # altro_page (hub di navigazione
    │                                  # secondaria: Storico, Ricorrenze, Imp.)
    ├── settings/                      # settings_page, categories_manage_page,
    │                                  # merchant_rules_page, import_page,
    │                                  # export_page, sync_page, gemini_page,
    │                                  # theme_page
    └── shared_widgets/                # root_scaffold (bottom nav), linked_
                                        # expense_sheet (spesa collegata a un
                                        # rimborso)
```

---

## 3. Schema del Database (Drift)

Schema normalizzato in 3NF. Tutte le tabelle usano `id` autoincrementale come PK.

### Categories
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| name | text | es. "Casa" |
| icon | text | emoji o codice icona |
| type | enum(income, expense) | |
| color | int (ARGB) | per grafici |
| isDefault | bool | non cancellabile se true |

### SubCategories
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| categoryId | int (FK → Categories) | |
| name | text | es. "Spesa" |
| icon | text | |

### Merchants
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| name | text (unique) | nome normalizzato es. "Esselunga" |
| defaultCategoryId | int (FK, nullable) | |
| defaultSubCategoryId | int (FK, nullable) | |

### MerchantRules
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| pattern | text | regex, es. `ESSEL.*` |
| categoryId | int (FK) | |
| subCategoryId | int (FK) | |
| priority | int | per gestire conflitti tra regex |
| isUserDefined | bool | true se creata da apprendimento automatico |

### Transactions
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| date | dateTime | |
| amount | real | sempre positivo, il segno lo dà `type` (+ `isRefund`, v. sotto) |
| type | enum(income, expense) | |
| categoryId | int (FK) | |
| subCategoryId | int (FK, nullable) | |
| merchantId | int (FK, nullable) | riservato: tabella Merchants non ancora popolata |
| note | text (nullable) | |
| isExtraordinary | bool | esclusa di default da statistiche/previsione Dashboard |
| isRefund | bool | rimborso ricevuto: resta nella categoria di spesa ma sottratto dal totale netto |
| receiptImagePath | text (nullable) | path locale foto scontrino |
| recurringId | int (FK, nullable) | valorizzato se generata da ricorrenza |
| refundOfId | int (nullable, no FK) | se `isRefund`, id della spesa collegata (auto-riferimento; niente vincolo FK per non ostacolare le cancellazioni soft-delete) |
| createdAt | dateTime | |

### Budgets
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| categoryId | int (FK, nullable) | null = budget globale |
| period | enum(monthly, yearly) | |
| amount | real | |
| startDate | dateTime | per storicizzare cambi di budget nel tempo |

### RecurringTransactions
| Campo | Tipo | Note |
|---|---|---|
| id | int (PK) | |
| description | text | es. "Netflix" |
| amount | real | |
| type | enum(income, expense) | |
| categoryId | int (FK) | |
| subCategoryId | int (FK, nullable) | |
| frequency | enum(weekly, monthly, yearly) | |
| dayOfMonth | int (nullable) | |
| nextOccurrence | dateTime | |
| active | bool | |

### Settings
| Campo | Tipo | Note |
|---|---|---|
| key | text (PK) | es. "themeMode", "currency" |
| value | text | |

### Campi di sync (aggiunti a tutte le tabelle sopra, **implementati in M7**)

Per supportare la sincronizzazione multi-dispositivo via Turso, ogni tabella riceve inoltre:

| Campo | Tipo | Note |
|---|---|---|
| updatedAt | dateTime | usato per il conflict-resolution last-write-wins |
| isDeleted | bool | soft delete, necessario perché le cancellazioni vanno propagate in sync |
| syncId | text (nullable, unique) | UUID stabile tra dispositivi; l'id intero locale non è valido tra dispositivi diversi. Backfillato automaticamente all'avvio per le righe che non lo hanno ancora (`AppDatabase._backfillSyncIds`), toccando anche `updatedAt` così le righe riparate non restano escluse dal push |

### Relazioni
```
Categories 1—N SubCategories
Categories 1—N Transactions
SubCategories 1—N Transactions
Merchants 1—N Transactions
Merchants 1—N MerchantRules (indiretto via categoria proposta)
Categories 1—N Budgets
RecurringTransactions 1—N Transactions (generate)
```

---

## 4. Flusso di Navigazione

```
                       ┌─────────────┐
                       │  Home (tab) │
                       └──────┬──────┘
        ┌───────────┬─────────┼─────────┬────────────┐
        ▼           ▼         ▼         ▼            ▼
   Dashboard     Budget   [FAB +]   Ricorrenze   Impostazioni
   (tab)         (tab)       │        (tab)          (tab)
                             │                         │
                  ┌──────────┴──────────┐    ┌─────────┴─────────┐
                  ▼                     ▼    ▼                   ▼
          Nuova Operazione      Scansiona   Categorie      Regole Merchant
             (manuale)           Scontrino   (gestione)     (tabella editabile)
                  │                  │                          │
                  ▼                  ▼                          ▼
             [Salva] → Home    Anteprima OCR              Import/Export Excel
                              → conferma/modifica
                              → [Salva] → Home
```

Bottom Navigation Bar a 4 voci: **Home | Dashboard | Budget | Altro**. Le
sezioni secondarie (Storico, Ricorrenze, Impostazioni) sono raggruppate sotto
**Altro** e si aprono a schermo intero, per non superare le 5 voci consigliate
da Material (in origine erano previste 5 voci, poi salite a 6 aggiungendo lo
Storico: da qui il raggruppamento).
Il pulsante **FAB centrale "Nuova Operazione"** apre un bottom sheet con due opzioni: *Inserimento manuale* / *Scansiona scontrino*.
**Ricerca** è accessibile da un'icona in Home/Dashboard (non tab, per non affollare la nav bar).

---

## 5. Wireframe delle Schermate Principali

### Home
```
┌─────────────────────────────────┐
│  Ciao 👋              🔍  ⚙️    │
│                                  │
│ ┌─────────────┐ ┌─────────────┐ │
│ │ Saldo Budget│ │ Saldo Reale │ │
│ │  +550,00 €  │ │  +900,00 €  │ │
│ └─────────────┘ └─────────────┘ │
│                                  │
│  Budget utilizzato: ▓▓▓▓▓░░ 72% │
│                                  │
│  Entrate mese      Uscite mese  │
│   2.350 €           1.450 €     │
│                                  │
│  Ultime operazioni               │
│  🛒 Esselunga        -42,80 €   │
│  ⛽ Q8               -60,00 €   │
│  💳 Stipendio      +1.800,00 €  │
│                                  │
│         ┌───────────────┐       │
│         │   ＋ Nuova    │       │
│         └───────────────┘       │
│ Home  Dashboard  Ricorr  Budget │
└─────────────────────────────────┘
```

### Nuova Operazione (manuale)
```
┌─────────────────────────────────┐
│  ✕                    Salva ✔  │
│                                  │
│         42,80 €                 │
│      [tastierino numerico]      │
│                                  │
│  [ Entrata ] [ Uscita ●]        │
│                                  │
│  Categoria:   🏠 Casa      ▾    │
│  Sottocat.:   🛒 Spesa     ▾    │
│  Data:        Oggi         📅   │
│  Negozio:     (opzionale)       │
│  Note:        (opzionale)       │
└─────────────────────────────────┘
```
Obiettivo: 3-4 tap per salvare (importo già con focus tastierino, categoria più usata preselezionata).

### Scansione Scontrino
```
┌─────────────────────────────────┐
│         [Anteprima camera]      │
│                                  │
│        ⬚  inquadra scontrino    │
│                                  │
│            📷 Scatta            │
└─────────────────────────────────┘
        ↓ dopo OCR
┌─────────────────────────────────┐
│  Rilevato: ESSELUNGA             │
│  Importo:     42,80 €            │
│  Categoria:   🏠 Casa      ▾    │
│  Sottocat.:   🛒 Spesa     ▾    │
│                                  │
│  [ Conferma e Salva ]           │
└─────────────────────────────────┘
```
Se negozio sconosciuto → stessa schermata ma categoria/sottocategoria vuote con prompt "Scegli categoria per questo negozio" + toggle "Ricorda per la prossima volta" (crea automaticamente la MerchantRule).

### Dashboard
```
┌─────────────────────────────────┐
│  [Mese ▾] [Anno ▾] [Categoria▾] │
│                                  │
│   Andamento ultimi 12 mesi       │
│   ▁▂▃▅▇▆▄▃▅▇█▆  (line chart)    │
│                                  │
│   Spese per categoria            │
│   ◔ donut chart                 │
│                                  │
│   Top negozi                    │
│   1. Esselunga     320 €        │
│   2. Q8             180 €       │
└─────────────────────────────────┘
```

### Budget
```
┌─────────────────────────────────┐
│  Budget Mensile ▾        + Nuovo│
│                                  │
│  🏠 Casa        400€ ▓▓▓▓░ 320 │
│  🚗 Auto        150€ ▓▓░░░  60 │
│  🍔 Tempo Libero 250€ ▓▓▓▓▓ 260│ ⚠
└─────────────────────────────────┘
```

### Regole Merchant (Impostazioni)
```
┌─────────────────────────────────┐
│  Regole di Classificazione   +  │
│                                  │
│  ESSEL.*      → Casa / Spesa  ✎│
│  Q8.*         → Auto/Carburante✎│
│  AMAZON.*     → Acquisti      ✎│
│  ...                            │
└─────────────────────────────────┘
```
Ogni riga editabile/eliminabile; "+" apre form per aggiungere pattern regex → categoria/sottocategoria.

---

## 6. Piano di Sviluppo per Milestone

**M0 — Setup progetto** *(fondamenta)*
- Struttura cartelle Clean Architecture, tema M3 light/dark, routing go_router
- Setup Drift: tabelle + DAO base + seed categorie/sottocategorie di default
- ✅ **Completata**

**M1 — Core transazioni (MVP inseribile)**
- Entità/UseCase Transaction, repository, CRUD completo
- Schermata "Nuova Operazione" (manuale) con tastierino rapido
- Home base: saldo reale, ultime operazioni, FAB
- ✅ **Completata**

**M2 — Categorie e Budget** — ✅ **Completata**
- Gestione categorie/sottocategorie personalizzabili (CRUD) con riordino
  drag & drop (ordine salvato nella tabella Settings, nessuna modifica di
  schema)
- Modulo Budget a due livelli: piano annuale con budget totale impostato
  mese per mese, poi suddivisione del totale tra le categorie (anche per
  mesi futuri). Sforamento sempre consentito e segnalato (barre rosse/avvisi).
  Ogni mese conserva la propria storia (`startDate` = 1° del mese).
- Home completa: card "Saldo Budget" + % utilizzato (usa il totale mensile
  se impostato, altrimenti la somma delle allocazioni per categoria)
- Tassonomia categorie/sottocategorie di default aggiornata + reset seed
  versionato (`kSeedVersion`) per riallineare il DB senza cancellazioni manuali

**M3 — Scontrini** — ✅ **Completata**
- Fotocamera/galleria (mobile) + OCR Google ML Kit Text Recognition (offline)
- `receipt_parser_service` per estrazione negozio + totale dal testo OCR
- Tabella MerchantRules + `rule_matcher_service` (regex)
- Flusso apprendimento: negozio sconosciuto → chiedi categoria → crea regola;
  schermata gestione regole in Impostazioni
- **Estensione post-M3**: l'OCR+regex non è più il percorso primario — la
  foto viene analizzata da **Google Gemini** (AI cloud gratuita, API key
  personale in Impostazioni), più accurata; OCR+regex resta come fallback
  automatico offline o se la chiamata cloud fallisce. Un tentativo con
  vision-LLM locale (Ollama) è stato scartato per lentezza.

**M4 — Dashboard e Statistiche** — ✅ **Completata**
- Integrazione fl_chart: andamento mensile (`monthly_trend_chart`), spese per
  categoria (`category_donut`), per sottocategoria (`subcategory_bars`),
  totali annuali (`annual_totals`)
- Filtro mese in Dashboard

**M5 — Ricorrenze** — ✅ **Completata**
- CRUD movimenti ricorrenti (entità/usecase/repository/DAO, lista con
  pausa-riattiva e swipe-to-delete, schermata di creazione/modifica con
  frequenza settimanale/mensile/annuale e giorno del mese opzionale)
- Job di generazione automatica all'avvio app (`GenerateDueRecurring`):
  controlla le `nextOccurrence` dovute e recupera anche le occorrenze
  arretrate se l'app non veniva aperta da più periodi, avanzando la data
  della prossima occorrenza. Nessuna modifica di schema (la tabella
  `RecurringTransactions` esisteva già dallo scaffold M0).

**M6 — Ricerca, Import/Export** — ✅ **Completata**
- Ricerca full-text su negozio/categoria/importo/note/data (schermata Storico)
- Import CSV (parser tollerante, anteprima con righe valide/da saltare,
  inserimento atomico) ed **export CSV per anno** (`TransactionCsvExporter`,
  colonne compatibili con l'import → round-trip senza perdite, UTF-8 con BOM,
  salvataggio via file picker). Export `.xlsx` e condivisione mobile rimandati
  come possibili estensioni.

**M7 — Sync multi-dispositivo (Turso)** — ✅ **Completata**
- Setup database Turso (piano Free), sync via API HTTP (Hrana), non embedded
  replica libSQL (v. sezione 1 per il perché)
- `TursoSyncService`: push/pull bidirezionale per 6 tabelle, gestione
  `updatedAt`/`isDeleted`/`syncId`, isolamento errori per tabella, timeout HTTP
- Icona di stato in AppBar + banner ben visibile in Home se non configurata/in errore
- Build desktop Windows (attiva) + Android (permesso INTERNET, applicationId
  dedicato, CI); macOS/Linux non generate

**M8 — Rifinitura** — 🔧 **In corso**
- Fix bug critici del motore di sync (isolamento errori, filigrana su righe
  scartate, backfill syncId che non toccava `updatedAt`)
- Audit best-practice: bug silenziosi, memory leak, dipendenze inutilizzate
- Riparazione doppioni categorie/sottocategorie/regole dopo sync multi-dispositivo
  (`dedupe_default_taxonomy`, eseguita a ogni avvio)
- Presenti 23 test unitari (parser CSV, receipt parser, rule matcher) + 1
  smoke widget test, non lanciati in CI
- Ancora da fare: animazioni, test su repository/usecase/sync, test in CI

---

## Note tecniche aggiuntive

- **Librerie effettivamente usate (tutte gratuite):** `drift` + `sqlite3_flutter_libs` (DB locale), `http` (client Turso HTTP e Gemini — niente `libsql_dart`, v. sezione 1), `flutter_secure_storage` (credenziali Turso + API key Gemini), `google_mlkit_text_recognition` + `camera`/`image_picker` (scontrini), `fl_chart` (dashboard), `go_router` (routing), `flutter_riverpod` (state/DI), `csv` + `file_picker` (import/export), `intl`, `uuid`, `collection`.
- **Piattaforme generate:** Windows desktop e Android. macOS/iOS/Linux non generate (aggiungibili con `flutter create --platforms=<piattaforma> .` se servisse in futuro).
- **Turso — piano Free:** sufficiente per uso personale; nessuna carta di credito richiesta per l'attivazione.
- **Performance inserimento:** categoria/sottocategoria più usate vengono precaricate come default nel form manuale, riducendo a 3-4 tap il tempo di inserimento.

---

**Stato attuale (28 lug 2026):** tutte le milestone M0-M7 completate. M8
(rifinitura) in corso: fix critici al motore di sync Turso (isolamento errori
per tabella, backfill syncId, timeout HTTP, alert su Home), sostituzione della
scansione scontrini con Google Gemini (fallback su OCR ML Kit), audit
best-practice del codice. Test: 23 unitari su `csv_transaction_parser`,
`receipt_parser_service`, `rule_matcher_service` + 1 smoke widget test
(`test/`) — non ancora eseguiti in CI (`android-build.yml` compila l'APK ma
non lancia `flutter test`), e senza copertura su repository/usecase/DAO o
sul motore di sync. Ancora da fare per M8: animazioni/empty states e ampliare
i test automatici.

> NOTA PIATTAFORME: generate **Windows** (`windows/`) e **Android**
> (`android/`, con `applicationId` dedicato, permesso INTERNET e CI). Per
> aggiungere altre piattaforme: `flutter create --platforms=<piattaforma> .`,
> poi verificare permessi/`minSdk` per `google_mlkit_text_recognition` e
> `camera` (≥ 21).

> NOTA BUILD: modifiche allo schema Drift o ai provider Riverpod richiedono
> `dart run build_runner build --delete-conflicting-outputs`. Lo schema DB è
> alla versione **6** (v. `AppDatabase.schemaVersion` in `app_database.dart`).
