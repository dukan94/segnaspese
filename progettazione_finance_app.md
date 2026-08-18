# Progettazione Completa — App Finanze Personali (Flutter)

> Documento di design originale, mantenuto aggiornato allo stato reale
> dell'implementazione (v. sezione 6 per lo stato milestone e le note a fondo
> pagina). **Ogni modifica non banale — nuova milestone, estensione, fix
> strutturale — va categorizzata e documentata qui PRIMA di scrivere codice**
> (v. "Processo per nuove milestone" in fondo alla sezione 6), non solo
> concordata a voce: l'obiettivo è che lo stato scritto qui sia sempre quello
> vero, milestone per milestone, come per M0-M8.

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
> `import_export_repository` (il CSV non ha bisogno di un repository
> dedicato, v. sotto), niente cartella `constants/` (icone e regex vivono
> accanto a chi le usa). La tabella `Merchants` (schema pronto ma mai
> collegata a un DAO/repository/UI/sync in un anno di sviluppo) è stata
> rimossa in M35 — v. sezione 6.

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
│   │                                  # budget, recurring
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
│   │   │   ├── app_database.dart     # Drift @DriftDatabase (schemaVersion 8)
│   │   │   ├── tables/               # transactions, categories, subcategories,
│   │   │   │                         # merchant_rules, budgets, recurring,
│   │   │   │                         # settings (niente merchants, M35)
│   │   │   └── daos/                 # transaction, category, merchant_rule,
│   │   │                              # budget, recurring
│   │   └── seed/                     # default_categories/subcategories/
│   │                                  # merchant_rules_seed, seed_runner,
│   │                                  # dedupe_default_taxonomy (riparazione
│   │                                  # doppioni post-sync multi-dispositivo),
│   │                                  # repair_orphaned_subcategories
│   ├── services/
│   │   ├── turso_http_client.dart    # client HTTP puro Dart per l'API Hrana
│   │   ├── turso_sync_service.dart   # push/pull bidirezionale, conflict res.
│   │   ├── sync_service.dart         # interfaccia SyncService + SyncStatus
│   │   ├── gemini_vision_service.dart # lettura scontrino via Google Gemini
│   │   ├── gemini_api_key_store.dart # API key Gemini in flutter_secure_storage
│   │   ├── google_sheets_service.dart # bridge temporaneo (Admin), service account
│   │   ├── google_sheets_row_formatter.dart # colonne del foglio "Copia di Spese"
│   │   ├── safe_transaction_deletion_service.dart # hard delete/purge con
│   │   │                              # conferma remota (Admin, v. sezione 6 M9)
│   │   └── transaction_duplicate_finder.dart # doppioni di contenuto in pull sync
│   ├── mappers/                      # Drift row ↔ Domain entity
│   └── repositories_impl/            # transaction, category, merchant_rule,
│                                      # budget, recurring
│
├── domain/services/
│   ├── bank_statement_parser.dart    # interfaccia comune import estratto conto
│   ├── bancoposta_statement_parser.dart # prima implementazione (Poste/BancoPosta)
│   └── statement_duplicate_matcher.dart # doppioni con tolleranza (± giorni)
│
└── presentation/
    ├── home/                          # home_page, home_providers, widgets/
    │                                  # (balance_card, budget_summary_card,
    │                                  # monthly_stats_row, recent_transactions)
    ├── transaction/                   # add_transaction_page (manuale +
    │                                  # modifica + rimborso collegato + modalità
    │                                  # "bozza" per l'import estratto conto),
    │                                  # widgets/ (amount_keypad, category_picker)
    ├── receipt/                       # receipt_scan_page (foto/galleria +
    │                                  # Gemini/OCR su mobile, testo su desktop)
    ├── dashboard/                     # dashboard_page/providers, widgets/
    │                                  # (monthly_trend_chart, category_donut,
    │                                  # subcategory_bars, annual_totals)
    ├── budget/                        # budget_page, budget_month_page,
    │                                  # budget_providers, widgets/
    ├── recurring/                     # recurring_list_page, recurring_edit_page
    │                                  # (numero di occorrenze finito opzionale)
    ├── history/                       # history_page (ricerca full-text, anche
    │                                  # per sottocategoria + elenco movimenti)
    ├── statement_import/              # statement_import_page (import estratto
    │                                  # conto bancario, un parser per banca)
    ├── altro/                         # altro_page (hub di navigazione
    │                                  # secondaria: Storico, Ricorrenze, Imp.)
    ├── settings/                      # settings_page, categories_manage_page
    │                                  # (blocco nomi duplicati + "Unisci con..."),
    │                                  # merchant_rules_page, export_page,
    │                                  # sync_page, gemini_page, theme_page,
    │                                  # admin_page (import CSV, bridge Sheets,
    │                                  # eliminazione definitiva/pulizia dati)
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
| active | bool | si disattiva da sola al raggiungimento di `totalOccurrences` (M14) |
| totalOccurrences | int (nullable) | schema v7 (M14): null = a tempo indeterminato |
| occurrencesGenerated | int | schema v7 (M14): contatore, parte da 0 |

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

**M8 — Rifinitura** — ✅ **Completata**
- Fix bug critici del motore di sync (isolamento errori, filigrana su righe
  scartate, backfill syncId che non toccava `updatedAt`)
- Audit best-practice: bug silenziosi, memory leak, dipendenze inutilizzate
- Riparazione doppioni categorie/sottocategorie/regole dopo sync multi-dispositivo
  (`dedupe_default_taxonomy`, eseguita a ogni avvio)
- Empty states coerenti + animazioni leggere (conteggio numeri, fade-in liste)
- Tema unificato su un solo seed color (dall'icona dell'app) per chiaro/scuro,
  al posto delle 4 varianti scure indipendenti; rename utente a "Tally" (solo
  UX: titolo, nome visibile sotto l'icona Android, doc — applicationId, nome
  pacchetto Dart e namespace UUID dei seed di default restano invariati)
- **CI attiva** (`.github/workflows/ci.yml`): `flutter analyze` + `flutter test`
  su ogni push e PR, con rigenerazione del codice (`build_runner`)
- Copertura test estesa: 13 file di test in `test/` (parser CSV, receipt parser,
  rule matcher, duplicate finder, **motore di sync Turso**, repair sottocategorie
  orfane, widget animati, **DAO ricorrenze/categorie/budget/transazioni** —
  date-math occorrenze, riordino con gap-fill, upsert budget, filtri ricerca —
  + 1 smoke widget test). Repository impl e usecase restano senza test dedicati:
  sono delega pura al DAO sottostante, senza logica propria da verificare.

**M9 — Admin e manutenzione dati** *(29 lug 2026)* — ✅ **Completata**
- Nuova pagina **Impostazioni > Admin** (`admin_page.dart`, nessuna password,
  solo fuori dal flusso normale): ospita l'import CSV (spostato da
  Impostazioni) e la configurazione del bridge Google Sheets.
- **Bridge Google Sheets**: finché attivo, ogni transazione salvata da
  `addTransactionProvider` (entrata o uscita, non il bulk import CSV, non le
  ricorrenze generate automaticamente, non modifiche/cancellazioni successive)
  viene copiata in background sul foglio Google "Copia di Spese" già usato a
  mano da Mario, con lo stesso schema di colonne (`Data;Quanto;Sub Categoria;
  Note;Tipologia Spesa;Categoria;Tipologia`, dedotto da un export CSV locale
  non versionato del foglio stesso). `testConnection` verifica anche che
  l'intestazione reale del tab combaci con quella attesa, non solo che il tab
  esista. Autenticazione **service account** (`googleapis`/`googleapis_auth`),
  non OAuth interattivo (`google_sign_in` non supporta Windows desktop).
  **Temporaneo**: da disattivare (switch in Admin) quando l'app sarà completa
  e testata al 100%.
- **Gestione transazioni** (`safe_transaction_deletion_service.dart`): il DB
  fa di norma solo soft delete. Admin aggiunge due modi di eliminare *per
  sempre* (irreversibili, solo tabella `Transactions`): ricerca puntuale +
  eliminazione, o "Pulisci database" (bulk sulle già soft-deleted).
  `SafeTransactionDeletionService` è l'unico punto d'accesso: prima di ogni
  hard delete/purge fa un tentativo di sync (best-effort) e poi LEGGE
  DIRETTAMENTE dal server se quella riga risulta davvero cancellata, prima di
  eliminarla fisicamente — copre righe scartate in silenzio dal push, upsert
  LWW che non aggiorna nulla (clock skew), sync di sfondo già in corso.
  `TursoSyncService.syncNow()` non ha più una guardia di rientranza
  silenziosa (una chiamata concorrente aspetta quella in corso e ne lancia
  comunque una fresca).
- **Fix reattività riordino categorie/sottocategorie** (`category_dao.dart`):
  il riordino drag & drop non si vedeva nel menù di "Nuova Operazione" finché
  non si riavviava l'app (stream Drift che legge da una tabella diversa da
  quella osservata, v. CLAUDE.md "Stream Drift che dipendono da un'altra
  tabella"). Fix: `_combineLatest2` combina la query principale con uno
  stream sull'intera tabella `Settings`.

**M10 — Icona app e splash screen "Tally"** *(31 lug 2026)* — ✅ **Completata**
- Icona adattiva Android (API 26+) + fallback legacy, splash screen nativo
  pre/post Android 12, icona Windows multi-risoluzione (16–256,
  `tool/generate_windows_icon.ps1`, necessario oltre a
  `flutter_launcher_icons` che scrive una sola risoluzione). Stessi colori
  del tema (crema/ambra), sorgenti in `assets/icon/` (v. CLAUDE.md per il
  comando di rigenerazione completo).

**M11 — Robustezza doppioni transazioni pre-sync + avviso doppioni manuali**
*(31 lug – 1 ago 2026)* — ✅ **Completata**
- Fix crash sync (`transaction_duplicate_finder.dart` assumeva al massimo 1
  candidato locale identico; con 2+ candidati preesistenti lanciava
  un'eccezione che bloccava il pull di tutte le transazioni). Fix
  definitivo: con 1+ candidati che combaciano su tutti i campi, la riga
  remota è comunque riconosciuta come duplicata (nessuna nuova inserita) —
  "se un dispositivo ha già sincronizzato, quello stato va rispettato".
- Pulizia una tantum del backlog di doppioni storici pre-sync (749/796
  transazioni doppie sul dispositivo di Mario, causa probabile: storico
  importato indipendentemente su più device prima che la sync esistesse):
  554 righe soft-deleted, backup pre-pulizia conservato.
- **Avviso doppione in "Nuova Operazione"**: al salvataggio, se esiste già
  una spesa con stessa data/categoria/importo, avvisa con link alla spesa di
  riferimento prima di confermare. Fix successivo lo stesso giorno:
  l'avviso interroga il database, non una cache in memoria potenzialmente
  stale.
- V. memoria `project_transaction_duplicates_pre_sync` per il dettaglio
  completo dell'incidente e della pulizia.

**M12 — Build Android release funzionante** *(1 ago 2026)* — ✅ **Completata**
- `flutter build apk --release` falliva per un problema R8/ProGuard
  preesistente (riferimenti a classi ML Kit per alfabeti mai usati
  dall'app). Fix in `android/app/proguard-rules.pro`. Release ~95MB contro
  ~200MB del debug. CI (`android-build.yml`) continua a buildare debug per
  scelta esplicita di Mario; il fix resta disponibile per quando servirà.

**M13 — Blocco doppioni categoria + strumento "Unisci con..."**
*(2 ago 2026)* — ✅ **Completata**
- UI blocca in `categories_manage_page.dart` la creazione/rinomina di una
  categoria o sottocategoria con un nome già esistente (case-insensitive).
- Nuova azione **"Unisci con..."**: sposta transazioni/regole
  merchant/budget/ricorrenze dalla categoria o sottocategoria sorgente a
  quella scelta come destinazione (anche verso un'altra categoria padre per
  le sottocategorie), poi elimina la sorgente. Rifiuta di unire una
  categoria che ha ancora sottocategorie attive con dati collegati.
- Pulizia una tantum dei doppioni `Casa`/`Salute`/`Viaggio` (default vs
  ricreate a mano da Mario con lo stesso nome). Verificato end-to-end da
  Mario su 2 dispositivi dopo il rilascio (v. memoria
  `project_category_default_vs_custom_duplicates`).

**M14 — Ricorrenze a numero di occorrenze finito** *(3 ago 2026)* — ✅ **Completata**
- Schema v7: colonne `totalOccurrences`/`occurrencesGenerated` su
  `RecurringTransactions` (v. sezione 3). Campo opzionale nel form; se vuoto
  la ricorrenza resta a tempo indeterminato come prima. `generateDue` si
  ferma da sola al tetto impostato (anche recuperando occorrenze arretrate)
  e mette la ricorrenza in pausa. Nessuna riattivazione automatica se il
  tetto viene rialzato.
- **Bug reale scoperto appena rilasciato**: `_ensureRemoteSchema()` crea le
  tabelle remote Turso con `CREATE TABLE IF NOT EXISTS`, che non altera una
  tabella già esistente — sul database Turso già in uso di Mario, le due
  colonne nuove non arrivavano mai sul remoto ("no such column"). Fix:
  `_addColumnIfMissing` (PRAGMA table_info + ALTER se manca), da applicare
  ad ogni futura colonna aggiunta a una tabella già sincronizzata (v.
  CLAUDE.md "Sync (Turso) — dettaglio critico").

**M15 — Import estratto conto bancario** *(5 ago 2026)* — ✅ **Completata**
- Feature utente vera (non un tool Admin), voce propria in Impostazioni.
  Un parser per banca (`domain/services/bank_statement_parser.dart`), prima
  implementazione Poste Italiane/BancoPosta (xlsx da "Lista movimenti").
  Categorizzazione automatica riga per riga via `RuleMatcherService`
  (stesse regole degli scontrini), editing inline di ogni riga (stessa
  `AddTransactionPage` in modalità "bozza"), doppioni con tolleranza
  (±3 giorni, stesso importo/tipo — più permissiva della sync perché nota/
  categoria dedotte dall'estratto conto raramente combaciano con
  l'inserimento manuale).
- **Estensione post-M15 — bug reale, segnalato da Mario (16 ago 2026)**:
  il parser leggeva la data dalla colonna sbagliata, **Data Contabile**
  (quando la banca registra il movimento, può slittare di giorni) invece
  di **Data Valuta** (quando il movimento incide sul saldo, molto più
  vicina al giorno reale della spesa) — la colonna 0 invece della colonna
  1 dello stesso foglio. Fix in `bancoposta_statement_parser.dart`
  (`_date(at(1))` invece di `at(0)`; la colonna 0 resta usata solo per
  individuare la riga di intestazione). Aggiornato anche il commento in
  `statement_duplicate_matcher.dart`, la cui tolleranza di ±3 giorni era
  motivata proprio dallo scarto tipico della data contabile — resta comunque
  utile come margine di sicurezza. **Bug non emerso dai test esistenti**:
  tutte le fixture usavano la stessa data in entrambe le colonne, quindi non
  potevano distinguere quale delle due venisse davvero letta — test
  aggiornato con date diverse nelle due colonne apposta per impedire la
  stessa regressione in futuro.

**M16 — Rifiniture ricerca, dashboard e CI** *(5 ago 2026)* — ✅ **Completata**
- Ricerca in Storico estesa anche alla sottocategoria.
- Fix tooltip del grafico andamento mensile in Dashboard (formattazione e
  filtro per categoria non corretti).
- CI (`android-build.yml`): l'APK debug caricato ad ogni push su `main`
  saturava il quota storage Artifacts gratuito di GitHub (0.5GB) con la
  retention di default a 90 giorni — GitHub ha segnalato l'errore
  ("Artifact storage quota has been hit"). Fix: `retention-days: 3`
  sull'upload (v. CLAUDE.md "CI — build Android APK, quota storage
  Artifacts" per i dettagli, incluso il ritardo di 6-12h nel ricalcolo
  quota dopo una pulizia manuale).

**M17 — Migrazione schema locale idempotente** *(16 ago 2026)* — ✅ **Completata**
- Bug reale: una migrazione Drift interrotta a metà (processo ucciso, es. da
  Task Manager, o istanze duplicate avviate per errore sullo stesso file)
  può lasciare una colonna già aggiunta fisicamente ma `user_version` non
  aggiornato. Al riavvio, `onUpgrade` ritenta lo stesso `addColumn` su una
  colonna già esistente → `SqliteException("duplicate column name")`,
  eccezione non gestita in `main()` **prima** di `runApp()`: la finestra
  Windows non appare mai (si mostra solo al primo frame renderizzato), senza
  errore visibile — sembra che l'app "non si apra", non che sia crashata.
  Riscontrato realmente sul dispositivo di Mario (v. CLAUDE.md "Migrazioni
  schema locale (Drift) — insidia" per la diagnosi completa e il fix una
  tantum sul suo database).
- Fix strutturale: ogni `addColumn`/ALTER TABLE in `onUpgrade` (v2→v7) ora
  controlla `PRAGMA table_info` prima di eseguire (`_columnExists`), stesso
  principio già usato per lo schema remoto Turso (M14). Test di regressione
  in `test/app_database_migration_test.dart`.

**M18 — ✅ Completata — Fix sicurezza: API key Gemini non deve mai comparire
in un messaggio d'errore**
*(emersa da audit best-practice, 16 ago 2026)*
- Problema: `gemini_vision_service.dart` costruisce l'URL della chiamata
  Gemini con la API key in query string (`?key=$apiKey`). Se la richiesta
  fallisce per un problema di rete (es. offline durante uno scan scontrino),
  l'eccezione di basso livello del pacchetto `http` include l'URL completo
  (con la key) nel proprio `toString()` — messaggio che risale fino a
  `receipt_scan_page.dart` e viene mostrato **testualmente in una
  snackbar**. La key di Mario finirebbe quindi visibile a schermo in caso di
  errore di rete durante uno scan. Il `TimeoutException` nello stesso file
  non ha questo problema (messaggio già pulito) — serve lo stesso
  trattamento per gli altri tipi di eccezione di rete.
- **Fatto**: il blocco `catch (e)` generico in `analyzeReceipt` non
  interpola più l'eccezione originale nel messaggio (era `'Impossibile
  contattare Gemini: $e'`, ora un testo fisso senza `$e`); aggiunto un
  branch dedicato `on SocketException` per un messaggio leggermente più
  specifico ("nessuna connessione di rete") comunque senza echeggiare
  l'eccezione originale. Verificato il bridge Google Sheets: non ha lo
  stesso rischio (le credenziali passano per header/JWT nella libreria
  `googleapis_auth`, mai in query string) — nessuna modifica necessaria
  lì. Test dedicato di regressione rimandato a M23 (serve prima
  un'infrastruttura di test per questo servizio, oggi privo di qualunque
  copertura — v. M23); `flutter analyze` + `flutter test` (120/120)
  invariati dopo il fix.

**M19 — ✅ Completata — Gestione errori su cancellazione transazione
(Home/Storico)**
*(emersa da audit best-practice, 16 ago 2026)*
- Problema: `recent_transactions_list.dart` e `history_page.dart` chiamano
  `deleteTransactionProvider` senza try/catch — un fallimento (DB locked,
  disco pieno, ecc.) non produce alcun feedback in UI, in contraddizione
  con la regola dichiarata (ogni errore risale come eccezione fino a una
  snackbar).
- **Fatto**: entrambe le chiamate ora avvolte in try/catch con
  `showErrorSnackBar(context, 'Errore: $e')`, stesso pattern già usato in
  `add_transaction_page.dart`/`budget_amount_dialog.dart`/
  `merchant_rules_page.dart`/`categories_manage_page.dart`. Nessun altro
  call-site di `deleteTransactionProvider` trovato in `lib/` oltre questi
  due. `flutter analyze` + `flutter test` (120/120) invariati.

**M20 — ✅ Completata — Verifica tag `+eol` su `sqlite3_flutter_libs`**
*(emersa da audit dipendenze, 16 ago 2026)*
- Problema: `flutter pub outdated` segnala `sqlite3_flutter_libs` 0.5.42 (in
  uso) → `0.6.0+eol` disponibile. Il significato esatto di quel tag non è
  stato verificabile senza accesso affidabile a internet durante l'audit;
  essendo il pacchetto che fornisce i binari SQLite nativi (DB locale core),
  merita un controllo prima di ignorarlo.
- **Fatto (investigazione, nessun codice toccato)**: confermato via pub.dev
  + changelog Drift + issue tracker che `0.6.0+eol` è deliberatamente
  svuotato — dalla versione 3.x del pacchetto `sqlite3`, la gestione dei
  binari nativi non richiede più `sqlite3_flutter_libs`, quella release
  serve solo a segnalarlo. **Non è però un aggiornamento banale**: Drift
  vincola `sqlite3` a `^2.4.6` fino alla 2.31.x compresa; il supporto a
  `sqlite3` 3.x arriva solo da **Drift 2.32.0** ("potentially breaking
  change" dichiarato nel changelog Drift), e questo progetto è fermo a
  `drift`/`drift_dev` 2.28.x (2.34.x disponibile). Serve quindi prima
  aggiornare Drift a ≥2.32, poi rimuovere/aggiornare
  `sqlite3_flutter_libs` seguendo la guida ufficiale
  `UPGRADING_TO_V3.md` di `sqlite3.dart` — non un'operazione isolata.
  L'upgrade vero e proprio è spostato dentro **M24** (aggiornamento
  dipendenze), dove va comunque fatto un pacchetto alla volta con build
  reale: qui tocca il layer DB core, quindi va trattato come il passo più
  delicato di quella milestone, con una build Windows reale avviata e
  verificata dopo, non solo `flutter test`.

**M21 — ✅ Completata — Timeout sulle chiamate Google Sheets (bridge Admin)**
*(emersa da audit gestione errori, 16 ago 2026)*
- Problema: `google_sheets_service.dart` (`appendRow`, `testConnection`)
  non ha nessun `.timeout(...)` esplicito, a differenza di
  `turso_http_client.dart` e `gemini_vision_service.dart` (30s con commento
  dedicato). "Test connessione" in Admin può restare bloccato a tempo
  indefinito se la rete non risponde.
- **Fatto**: timeout di 30s (stessa costante `_networkTimeout`) su tutte e
  4 le chiamate di rete del file — autenticazione service account
  (`_client`), `appendRow`, e le due chiamate di `testConnection`
  (`spreadsheets.get` + `spreadsheets.values.get`) — ciascuna con messaggio
  d'errore dedicato in caso di `TimeoutException`. Verificato (v. M18) che
  nessun messaggio esponga credenziali: le eccezioni sollevate qui sono
  testo fisso, mai un'interpolazione dell'eccezione di rete originale.
  `flutter analyze` + `flutter test` (120/120) invariati.

**M22 — ✅ Completata — Isolamento errori nella sequenza di avvio
(main.dart)**
*(emersa da audit gestione errori, 16 ago 2026)*
- Problema: `runSeed`/`dedupeDefaultTaxonomy`/`repairOrphanedSubCategories`/
  `generateDueRecurringProvider` in `main.dart` girano in sequenza senza
  try/catch individuali — un'eccezione in uno qualsiasi impedisce
  `runApp()` (stessa classe di fragilità del bug M17, qui sugli altri 3
  step, non ancora protetti).
- **Decisione presa**: stesso trattamento per tutti e 4 gli step — sono
  tutti opportunistici/riparativi (seed, dedupe, riparazione
  sottocategorie, generazione ricorrenze), saltarne uno per una volta non
  perde dati, solo rimanda la riparazione/generazione al prossimo avvio;
  nessuno merita quindi una regola diversa dagli altri. Nuovo helper
  `_runStartupStep(label, step)` in `main.dart` avvolge ciascuno in
  try/catch, logga con `debugPrint` (stesso pattern di `_logSyncError`) e
  continua comunque — `runApp()` viene sempre chiamato, qualunque step
  fallisca. Verificato anche con build reale Windows (finestra compare
  regolarmente dopo il fix, non solo `flutter test`). `flutter analyze` +
  `flutter test` (120/120) invariati.

**M23 — ✅ Completata — Copertura test per logica critica priva di test**
*(emersa da audit copertura test, 16 ago 2026)*
- Problema: `gemini_vision_service.dart` (parsing/validazione output AI
  scontrini), `seed_runner.dart` (reset distruttivo condizionale),
  `dedupe_default_taxonomy.dart` (riparazione automatica a ogni avvio),
  `turso_http_client.dart` (encoding/decoding protocollo Hrana reale, oggi
  esercitato solo tramite `FakeTursoHttpClient` nei test di sync) non hanno
  nessun test dedicato, pur contenendo logica non banale con impatto
  diretto su dati reali.
- **Fatto**: 4 nuovi file di test (37 test in totale), stesso principio di
  `FakeTursoHttpClient` (test di produzione reale con solo il trasporto di
  rete sostituito):
  - `test/gemini_vision_service_test.dart` (13 test): estratto un metodo
    `sendRequest` sovrascrivibile da `GeminiVisionService.analyzeReceipt`
    (prima la chiamata `http.post` era inline), copre parsing (JSON
    pulito, virgola decimale, fence markdown, campi vuoti), tutti gli
    status HTTP (400/403/429/altro), candidates vuoti, JSON non valido —
    **e il regression test per M18**: verifica che nessun messaggio
    d'errore contenga mai la API key, nemmeno quando l'eccezione originale
    la includerebbe (URL con la key confermato presente, messaggio
    verificato pulito).
  - `test/seed_runner_test.dart` (4 test): primo avvio, versione già
    allineata (dati utente non toccati), reset pulito con versione seed
    cambiata (transazioni/ordinamenti svuotati, tassonomia vecchia
    rimossa), versione cambiata ma nessuna categoria presente (reset
    saltato).
  - `test/dedupe_default_taxonomy_test.dart` (8 test): dedupe
    categorie/sottocategorie/regole/budget con repointing corretto,
    categorie non-default e regole utente mai toccate, righe senza syncId
    ignorate, nessun doppione → no-op.
  - `test/turso_http_client_test.dart` (12 test): stesso principio di
    `sendRequest` sovrascrivibile applicato a `TursoHttpClient.execute`
    (diverso da `FakeTursoHttpClient`, che sovrascrive `execute` per
    intero bypassando l'encoding/decoding reale) — copre
    `_normalizeBaseUrl`, `_encodeArg` per ogni tipo (int/double/bool/null/
    String), `_decodeCell` per ogni tipo (incluso un intero a 64 bit per
    verificare che la precisione non si perda), batch multi-statement,
    errori SQL/HTTP/rete.
  - `flutter analyze` pulito, **157/157 test** (120 + 37 nuovi).

**M24 — ✅ Completata — Aggiornamento dipendenze con gap major ampio**
*(emersa da audit dipendenze, 16 ago 2026)*
- Problema: `file_picker` (4 major indietro), `go_router` (3),
  `csv`/`flutter_secure_storage` (2 ciascuno) hanno accumulato breaking
  change; restare troppo indietro rende ogni futuro aggiornamento più
  rischioso e può far perdere fix di sicurezza a monte. Include anche
  l'upgrade `drift`/`drift_dev` a ≥2.32 + rimozione di
  `sqlite3_flutter_libs` (v. M20): il passo più delicato, tocca il DB
  locale core.
- **Fatto**, un pacchetto alla volta, changelog letto prima di ogni bump:
  - **`csv` 6→8**: `ListToCsvConverter` rimosso, sostituito da
    `Csv(fieldDelimiter:, lineDelimiter:).encode(...)` in
    `transaction_export_service.dart` (unico punto d'uso nel codice). Nuovo
    test di regressione (`transaction_export_service_test.dart`, non
    esisteva prima): formato invariato (intestazione, separatore `;`, CRLF,
    segno del rimborso).
  - **`flutter_secure_storage` 9→11** (in due tappe, 9→10→11, per
    sicurezza): nessuna firma cambiata per l'uso di questo progetto (solo
    `read`/`write`/`delete` di base, nessuna opzione platform-specific
    usata). Rischio investigato e scartato: il cambio di backend Windows
    (Credential Manager → file cifrato) era già avvenuto in una versione
    precedente non correlata (`flutter_secure_storage_windows` già a 3.1.2
    prima di questo aggiornamento) — il salto 9→11 non attraversa quella
    transizione.
  - **`file_picker` 8→12** (bump forzato insieme a `flutter_secure_storage`
    11, che richiede `win32 ^6.0.1` incompatibile con `file_picker ^8.x`):
    `FilePicker.platform` rimosso (metodi statici diretti),
    `pickFiles()`/`saveFile()` con tipi di ritorno cambiati
    (`FilePickerResult?`→`List<PlatformFile>`, `String?`→`Uri?`),
    `PlatformFile.bytes` rimosso a favore di `readAsBytes()` lazy. Migrati
    i 3 punti d'uso (`import_page.dart`, `statement_import_page.dart` verso
    `pickFile()` singolare invece di `pickFiles(allowMultiple: false)`
    deprecato; `export_page.dart` verso `uri.toFilePath()`).
  - **`go_router` 14→17**: zero modifiche di codice necessarie — nessun
    uso di `GoRouteData` (solo `GoRoute`/`builder` semplici) né percorsi
    con maiuscole, le due breaking change principali (case-sensitivity,
    firma `onExit`) non toccano questo progetto.
  - **`drift`/`drift_dev` 2.28→2.34 + rimozione `sqlite3_flutter_libs`**
    (passo più delicato, trattato con cura extra): `sqlite3` risolto
    automaticamente a 3.x da Drift 2.32+; `sqlite3_flutter_libs` rimosso
    dal pubspec (svuotato/eol, v. M20), `sqlite3` dichiarato come
    dipendenza diretta — il bundling dei binari nativi ora passa dai
    build hook di Dart (`native_toolchain_c`, nessuna configurazione
    manuale necessaria per l'uso senza cifratura di questo progetto).
    Zero codice applicativo toccato (nessun uso di `open.overrideFor` o
    import diretto di `sqlite3_flutter_libs` da rimuovere). **Verificato
    con build Windows reale pulita** (`flutter clean` prima, per escludere
    artefatti residui) **contro il database vero di Mario** (backup
    preventivo `finance_app.sqlite.backup-2026-08-16-pre-drift234-sqlite3`):
    `sqlite3.dll` ricostruito, nessun residuo del plugin rimosso,
    `PRAGMA integrity_check` → `ok`, `user_version` → 7, tutte le tabelle
    lette correttamente coi conteggi reali (655 transazioni, 42 categorie,
    ecc.) tramite uno script Dart di sola lettura, poi rimosso.
  - `flutter analyze` pulito, **159/159 test** (157 + 2 nuovi per l'export
    CSV) dopo ogni singolo bump, non solo alla fine.
- **Non fatto in questo giro** (gap minori, rischio/beneficio basso —
  restano per un futuro aggiornamento di routine): `fl_chart` 0.68→1.2,
  `google_mlkit_text_recognition`/`camera` (pre-1.0), `flutter_lints`
  4→6. `camera` risultava peraltro una dipendenza morta (mai importata,
  v. audit) — rimovibile a parte, non necessita di un bump.

> **Nota (non una milestone)**: l'audit ha anche confermato che le build
> Android "release" sono firmate con la stessa `debug.keystore` di CI —
> deliberato per ora (nessuna distribuzione su store), coerente con
> CLAUDE.md. Da rivedere solo se in futuro si distribuisce mai un APK
> release reale, non un'azione da fare ora.

**M25 — ✅ Completata — Rimborso con divisore (quota di una spesa condivisa)**
*(richiesta da Mario, 16 ago 2026)*
- Problema: da una spesa esistente, creare rapidamente un rimborso pari a
  una frazione (1/N) dell'importo originale, con nota facoltativa (di
  solito chi restituisce la quota, es. "Nicola"), senza passare dal form
  completo di "Nuova Operazione" — esempio concreto: spesa da 50€, divisore
  2 → rimborso di 25€. Nota terminologica: nell'uso comune il numero "2"
  viene chiamato "dividendo", ma matematicamente è il **divisore** (il
  dividendo sarebbe i 50€) — l'etichetta nel campo userà "Divisore" per
  chiarezza.
- Decisioni prese con Mario:
  - Data del rimborso creato: **oggi** (non la data della spesa originale).
  - Nota: **facoltativa** (coerente con lo stile del resto dell'app).
  - Divisore minimo accettato: **2** (dividere per 1 sarebbe un rimborso
    pieno, già coperto dal flusso manuale esistente — validazione inline
    se ≤1 o non numerico).
  - Posizione UI: **nuova icona in Storico**, accanto a "Rimborsa"
    (`Icons.currency_exchange`) esistente — icona separata (es.
    `Icons.call_split`), stesso filtro di visibilità (`tx.type == expense
    && !tx.isRefund`, righe 112-113 `history_page.dart`).
- Approccio tecnico (basato sul flusso di rimborso esistente, investigato
  prima di questa proposta):
  - Nuovo bottom sheet leggero (stesso stile di `linked_expense_sheet.dart`,
    non l'intero `AddTransactionPage`): mostra la spesa originale in sola
    lettura (importo, categoria/sottocategoria, data) per contesto, poi
    "Divisore" (numero intero) e "Note" (facoltativa), con anteprima live
    "Quota: X,XX €" che si aggiorna mentre si digita.
  - Al conferma, costruisce un `TransactionEntity`: `date` = oggi, `type` =
    `expense`, `categoryId`/`subCategoryId` ereditati dalla spesa originale
    (non modificabili, a differenza del flusso manuale), `amount` =
    originale/divisore arrotondato a 2 decimali (stesso pattern `_round2`
    già usato in `bancoposta_statement_parser.dart`), `note` = quella
    inserita (o null), `isRefund: true`, `refundOfId` = id della spesa
    originale.
  - Salvataggio tramite lo stesso `addTransactionProvider` già usato dal
    form manuale — stessa pipeline (bridge Google Sheets se attivo, stesso
    percorso di persistenza), nessuna duplicazione di logica.
  - Calcolo/arrotondamento/validazione isolati in un piccolo usecase
    dedicato in `domain/usecases/transaction/` (puro Dart, testabile senza
    Flutter) — la divisione con arrotondamento è l'unica vera logica di
    business della feature, merita un test dedicato.
  - **Fatto**: `BuildSplitRefund` (`domain/usecases/transaction/
    build_split_refund.dart`) — pura logica di calcolo/validazione (divide,
    arrotonda a 2 decimali, valida divisore ≥2/spesa con id/spesa normale
    non già rimborso o entrata), 10 test dedicati
    (`test/build_split_refund_test.dart`). Bottom sheet
    `showSplitRefundSheet` (`presentation/transaction/widgets/
    split_refund_sheet.dart`): spesa originale in sola lettura, campo
    "Divisore" (solo cifre, errore inline se <2), "Note" facoltativa,
    anteprima live "Quota: X,XX €". Nuova icona `Icons.call_split`
    ("Rimborso con divisore") in Storico accanto a "Rimborsa" esistente,
    stesso filtro di visibilità. Salvataggio tramite lo stesso
    `addTransactionProvider` del form manuale (stessa pipeline, bridge
    Google Sheets incluso).
  - **Non incluso in questa prima versione** (nessuna richiesta esplicita,
    nessun codice esistente da riusare): un tetto che impedisca di
    rimborsare più del dovuto sommando eventuali rimborsi già collegati
    alla stessa spesa — il flusso manuale esistente non ha questo
    controllo, quindi non è una regressione ometterlo qui.
- **Estensione post-M25** *(17 ago 2026, richiesta da Mario)*: il campo
  "Note" del bottom sheet si apre precompilato con la nota della spesa
  originale (se presente), invece che vuoto — resta modificabile, per poter
  aggiungere di seguito chi ha restituito la quota (es. nota spesa
  "Carburante per viaggio" → precompilato uguale, Mario aggiunge "Nicola" o
  "Famiglia" per sapere chi ha fatto il rimborso). Fix in
  `split_refund_sheet.dart`: `_noteController` inizializzato con
  `widget.expense.note ?? ''` invece che vuoto.

**M26 — ✅ Completata — Fondamenta layout desktop-adattivo**
*(richiesta da Mario, 16 ago 2026 — l'app "è scomoda da usare da pc")*
- Problema: `root_scaffold.dart` e tutte le pagine non avevano alcuna logica
  responsive — stessa bottom navigation bar e stesso layout a colonna
  singola pensato per il telefono, indipendentemente da quanto sia larga
  la finestra Windows. Confermato con un mockup HTML di confronto
  (Home attuale vs proposta), discusso e corretto insieme prima di questa
  proposta: niente grafici aggiunti solo per riempire lo spazio guadagnato,
  la finestra larga deve dare respiro (margini), non contenuto extra.
- **Fatto**:
  - `VisualDensity.adaptivePlatformDensity` in `app_theme.dart`
    (`_buildTheme`) — riduce padding/altezze dei componenti Material
    standard su desktop, invariato su Android.
  - `lib/core/utils/responsive.dart`: `kWideWindowBreakpoint = 900` +
    `isWideWindow(context)` su `MediaQuery.sizeOf`, usato da tutte le
    milestone successive.
  - `NavigationRail` in `root_scaffold.dart` sopra la soglia (bottom
    navigation bar invariata sotto) — le 4 destinazioni (Home/Dashboard/
    Budget/Altro) sono ora dichiarate una sola volta (`_navEntries`) e
    condivise tra i due widget di navigazione, invece di duplicate.
  - `ContentWidthLimiter` (`presentation/shared_widgets/`): centra il
    contenuto con una larghezza massima invece di stirarlo edge-to-edge,
    riusato da ogni pagina adattata nelle milestone seguenti (niente nuova
    "famiglia di card": le card continuano a condividere lo stesso
    `CardTheme` globale già esistente, che di per sé garantisce raggio/
    padding coerenti — non serviva introdurne uno nuovo specifico per
    desktop).
  - Verificato con `flutter run -d windows --release`: la finestra si apre
    di default a 1280×720 (sopra la soglia), quindi `NavigationRail` e i
    layout affiancati delle milestone seguenti sono stati esercitati subito
    all'avvio senza errori di layout (`RenderFlex` overflow ecc.) in console.

**M27 — ✅ Completata — Home adattiva da finestra larga**
*(mockup discusso e approvato con Mario, 16 ago 2026)*
- Problema: la Home (`BalanceCard`, `BudgetSummaryCard`, `MonthlyStatsRow`,
  Ultime operazioni) si stira a colonna singola anche su finestra larga.
- **Fatto** (adattato alle card reali, non alle card semplificate del
  mockup): `BalanceCard` ("Saldo mese"/"Saldo anno") e `BudgetSummaryCard`
  ("Saldo Budget" + barra) affiancate in un `Row` su finestra larga tramite
  il nuovo widget `_BalanceAndBudgetRow` — era già l'intento del wireframe
  originale (progettazione, sezione 5: "Saldo Budget │ Saldo Reale"),
  realizzabile ora che c'è spazio orizzontale per farlo. `MonthlyStatsRow`
  (Entrate/Uscite) era già una riga di 2 tile — invariata. Tutto racchiuso
  in `ContentWidthLimiter(maxWidth: 760)`. **Niente grafici in Home**
  (restano solo in Dashboard): lo spazio guadagnato resta respiro, non
  contenuto in più. Sotto la soglia, tutto impilato esattamente come oggi
  (`_BalanceAndBudgetRow` in modalità `Column`).

**M28 — ✅ Completata — Dashboard adattiva**
*(mockup discusso e approvato con Mario, 16 ago 2026)*
- Problema: i grafici della Dashboard (andamento mensile, spese per
  categoria, barre sottocategoria, totali annuali) erano impilati
  verticalmente anche su finestra larga.
- **Fatto**: nuovo widget `_ChartsSection` in `dashboard_page.dart` — su
  finestra larga, torta "Spese per categoria" + barre sottocategoria
  raggruppate in una colonna (`flex: 85`, rispondono insieme alla fetta
  selezionata), "Andamento 12 mesi" in un'altra colonna più larga
  (`flex: 115`, un grafico a linee legge meglio con più spazio orizzontale)
  — raggruppate per relazione funzionale (la selezione), non per "sono
  entrambi grafici". In modalità "Mese" (nessun andamento da mostrare)
  resta tutto in colonna: affiancare la sola torta a uno spazio vuoto non
  avrebbe senso. `AnnualTotals` (già una riga di 3 stat card) e il resto
  invariati, tutto in `ContentWidthLimiter(maxWidth: 960)`. Sotto la
  soglia, tutto impilato come oggi.
- **Revisione (17 ago 2026, richiesta da Mario)**: raggruppamento
  ribaltato — colonna sinistra ora **solo** la torta con la sua legenda;
  colonna destra **andamento 12 mesi sopra, barre sottocategoria sotto**
  (prima erano affiancate alla torta a sinistra). La sottocategoria segue
  comunque l'andamento nella stessa colonna quando c'è, non da sola a
  fianco della torta. Caso vuoto aggiornato di conseguenza: la torta resta
  da sola solo se **sia** l'andamento **sia** la sottocategoria mancano
  (vista "Mese" senza categoria selezionata) — se anche solo una delle due
  è presente, la torta viene comunque affiancata (prima serviva
  specificamente l'andamento per giustificare la riga).

**M29 — ✅ Completata — Budget adattivo**
*(mockup discusso e approvato con Mario, 16 ago 2026)*
- Problema: i 12 mesi (`budget_page.dart`) e le categorie del mese
  selezionato (`budget_month_page.dart`) erano liste verticali che
  costringevano a scorrere per vedere l'anno/la suddivisione per intero,
  pur essendo elementi comparabili e ripetuti — candidati naturali per una
  griglia.
- **Fatto**: nuovi widget `_MonthGrid` (`budget_page.dart`) e
  `_CategoryGrid` (`budget_month_page.dart`), stesso identico pattern —
  `GridView.builder` a 4 colonne (`SliverGridDelegateWithFixedCrossAxisCount`,
  `mainAxisExtent: 128`) su finestra larga, `Column` (comportamento odierno)
  sotto la soglia. Le tile (`_MonthTile`/`_CategoryBudgetTile`) restano
  esattamente le stesse, solo più compatte e affiancate invece che a piena
  larghezza una sotto l'altra — nessuna logica di calcolo toccata.
  `AnnualSummaryCard`/`_TotalCard` (blocchi singoli, non ripetuti) restano
  a piena larghezza sopra la griglia, non ne fanno parte. Tutto in
  `ContentWidthLimiter(maxWidth: 960)`.
- Correzione richiesta durante la revisione del mockup: l'icona "+" dei
  mesi/categorie non ancora impostati va in alto a destra della card
  (stessa posizione delle cifre spesa/totale sulle card già impostate),
  non come testo "Imposta →" in basso.
  - **Bug reale nella prima implementazione (16 ago 2026)**: la correzione
    era stata applicata solo al mockup HTML, non al codice Flutter reale —
    `_MonthTile`/`_CategoryBudgetTile` continuavano a mostrare "Imposta →"/
    "Aggiungi" anche nella griglia, perché `_MonthGrid`/`_CategoryGrid`
    (creati per M29) riorganizzano solo la disposizione delle tile
    esistenti, non il loro contenuto interno — la modifica al testo/icona
    andava fatta separatamente sulle tile stesse, passo dimenticato.
    Segnalato da Mario dopo aver visto l'app reale. Fix: nuovo widget
    condiviso `AddIcon` (`presentation/budget/widgets/add_icon.dart`),
    usato da entrambe le tile solo quando `isWideWindow(context)` — sotto
    la soglia (lista) il testo resta invariato, ha senso lì perché la riga
    è a piena larghezza.
  - **Secondo bug reale, stesso giorno**: nome mese/categoria e importi
    "speso/allocato" si sovrapponevano nella griglia — affiancati sulla
    stessa riga (`Expanded(nome) + Text(importi)`), non c'è spazio per
    entrambi in una colonna di griglia larga solo ~1/4 del contenuto,
    a differenza della riga a piena larghezza in modalità lista dove
    conviveva senza problemi. Stesso rischio anche per "Restano/Sforato" +
    "Da suddividere" (affiancati con uno `Spacer`). Segnalato da Mario dopo
    aver visto l'app reale (il mockup usava nomi/importi brevi che non
    mostravano il problema). Fix: nuovi widget `_GridMonthHeader`/
    `_GridRemainingStatus` (`budget_page.dart`) e `_GridHeader`
    (`budget_month_page.dart`) — nome e importi impilati su righe separate
    invece che affiancati, solo in modalità griglia; `mainAxisExtent`
    delle griglie alzato da 128 a 144 per il contenuto in più.
    Modalità lista (sotto la soglia) invariata: lì c'è spazio a sufficienza
    per la riga singola originale.

**M32 — ✅ Completata (17 ago 2026) — Sync immediata su inserimento/modifica/
cancellazione transazione**
*(richiesta da Mario, 17 ago 2026)*
- Problema: `TursoSyncService.syncNow()` partiva solo all'avvio, ogni 5
  minuti, al cambio di stato dell'app (`didChangeAppLifecycleState` in
  `app.dart`: `paused`/`detached`/`resumed`) e su richiesta manuale
  (Impostazioni > Sync) — mai subito dopo che una transazione veniva
  salvata/modificata/cancellata durante la sessione: un inserimento poteva
  restare solo locale fino al prossimo tick.
- **Fatto**: `addTransactionProvider`/`updateTransactionProvider`/
  `deleteTransactionProvider` (`core/di/transaction_providers.dart`) —
  prima solo `addTransactionProvider` era una funzione avvolta (per il
  bridge Google Sheets), gli altri due esponevano l'usecase "nudo" — ora
  tutti e tre lanciano `syncService.syncNow()` in background
  (`unawaited` + `catchError` → `debugPrint`, stesso identico pattern già
  in `main.dart`/`app.dart`: nessun errore mostrato all'utente, resta
  visibile solo da icona/banner di sync esistenti) subito dopo che il
  salvataggio locale è andato a buon fine. Nessun blocco della UI: il
  salvataggio resta istantaneo, la sync parte alle spalle: grazie al
  design "queue-and-refresh" di `syncNow()` (M9), più salvataggi ravvicinati
  non si accavallano.
  - **Cancellazione inclusa** (non solo inserimento/modifica come nella
    richiesta iniziale): stesso rischio, una cancellazione non
    sincronizzata prima di chiudere l'app potrebbe "ricomparire" da un
    altro dispositivo — confermato da Mario.
  - **Il timer ogni 5 minuti resta invariato** (richiesto esplicitamente da
    Mario): questo trigger si aggiunge, non lo sostituisce.
  - **Fuori scope, deliberatamente**: l'import CSV bulk (Admin, chiama
    `repository.addAll` direttamente) e le transazioni generate dalle
    ricorrenze all'avvio (`RecurringDao.generateDue`, chiama il DAO
    direttamente) non passano da questi provider — stesso perimetro già
    escluso dal bridge Google Sheets, e le ricorrenze sono comunque coperte
    dalla sync che parte subito dopo la loro generazione in `main.dart`.
  - `flutter analyze` pulito, **169/169 test invariati** (nessun test
    nuovo: il cambiamento aggiunge solo una chiamata fire-and-forget già
    ampiamente coperta dai test esistenti di `TursoSyncService`, senza
    nuova logica di business da verificare).

**M30 — ✅ Completata (17 ago 2026) — Storico adattivo**
- **Layout**: niente master-detail — stessa lista di oggi, solo centrata con
  larghezza massima tramite `ContentWidthLimiter` (stesso pattern di
  Home/Dashboard/Budget in M26-M29). Il tap continua ad aprire
  `AddTransactionPage` a schermo intero come oggi, nessun nuovo pattern di
  navigazione. Deciso esplicitamente da Mario tra le due opzioni proposte.
- **Contenuto della card ridisegnato** (vale sia sotto sia sopra la soglia
  larghezza — non è una differenza desktop/mobile, tocca `_HistoryTile` in
  generale): icona categoria a sinistra come oggi, poi la **data isolata**
  dal resto del testo (oggi è dentro la stringa `subtitle` unita con dei
  "·", va spostata in un suo spazio dedicato), poi la **Nota** come oggi,
  e **sotto la Nota la sottocategoria** (oggi il subtitle mostra il nome
  categoria, non sottocategoria — la sottocategoria è testo più specifico,
  l'icona a sinistra già comunica la categoria). A destra resta come oggi
  l'importo con segno + le icone di azione (modifica/rimborsa/rimborso con
  divisore/elimina). Da capire in fase di sviluppo dove riposizionare i tag
  "Rimborso"/"Straordinaria" (oggi in testa al subtitle unito) in questo
  nuovo schema — probabile accanto alla sottocategoria.
- **Sfondo card colorato solo per le entrate** (vale ugualmente su
  **Android e desktop**, non legato alla larghezza) — **rivisto da Mario
  dopo aver visto a schermo la prima versione con anche il rimborso
  colorato**: un rimborso (`tx.isRefund`) non ha più uno sfondo dedicato,
  resta identico a una spesa normale (`cardTheme` di oggi,
  `surfaceContainerHigh`). Solo:
  - Spesa (uscita non rimborso) e rimborso: colore invariato.
  - Entrata: verde. Colore chiaro scelto direttamente da Mario (17 ago
    2026): `#C9E59D`. Scuro derivato (non scelto da Mario, stesso criterio
    HSL: stessa tonalità/saturazione del chiaro, solo più scuro):
    `#344913`. Testo (`onIncomeContainer`): chiaro con una versione scura/
    satura della stessa tonalità (`#436B06`); scuro riusando il colore
    chiaro stesso scelto da Mario come testo sul fondo scuro (`#C9E59D`),
    che garantisce automaticamente la stessa armonia tra chiaro e scuro
    invece di introdurre una quarta tonalità scollegata.
  - **Vincolo esplicito di Mario**: i colori (e in generale le scelte
    grafiche) vanno scritti come **costanti/variabili centralizzate**,
    modificabili da un solo punto — stesso pattern già in uso in
    `app_theme.dart` per `warningContainer`/`onWarningContainer`
    (indipendenti dal seed, fissi per chiaro/scuro). Nuovo metodo:
    `AppTheme.incomeContainer`/`onIncomeContainer`, stesso schema. Non
    sparpagliare i colori come literal `Color(0x...)` dentro
    `history_page.dart`.
- **Icona "spesa con rimborso collegato"**: le card di una spesa con almeno
  un rimborso collegato (`refundOfId` di una o più transazioni uguale
  all'id di questa spesa — non è detto sia una sola, v. M25 "nessun tetto
  sui rimborsi collegati") mostrano un **cerchietto colorato** (badge)
  accanto alla Nota con dentro l'icona `Icons.link` — richiesto da Mario
  (17 ago 2026, seconda revisione) al posto della sola icona piatta usata
  nella prima versione, una volta tolto lo sfondo colorato del rimborso.
  Colore del badge scelto da Mario, fisso (non differenziato chiaro/scuro,
  a differenza dello sfondo entrata sopra — è un cerchietto piccolo, non
  un'intera card): `#E5E39F` (`AppTheme.refundedBadgeColor`), icona
  `#6B6806` (`AppTheme.onRefundedBadgeColor`) per contrasto. Stesso
  significato di `Icons.link` già in uso oggi ma nella direzione opposta
  (`onShowLinked` sulla card del RIMBORSO, per risalire alla spesa
  originale). Al tap, mostra il/i rimborsi collegati a QUESTA spesa (nuovo:
  oggi esiste solo la direzione rimborso→spesa via
  `linked_expense_sheet.dart`; serve un'estensione o un widget analogo per
  la direzione spesa→rimborsi, che gestisca anche il caso di più di un
  rimborso collegato). Vale ugualmente su Android e desktop.
- **Fatto**: implementato su branch `feature/history-adaptive-m30`
  (`_HistoryTile` in `history_page.dart`, nuovi colori in `app_theme.dart`,
  nuovo `linked_refunds_sheet.dart`), verificato con build Windows reale a
  ogni iterazione (2 revisioni sui colori dopo aver visto l'app a schermo,
  v. sopra) prima del merge su `main`. `flutter analyze` pulito, **169/169
  test** invariati (nessun test nuovo: la logica toccata è solo
  presentazione/tema, senza calcoli o casi limite da coprire — stesso
  principio già seguito per M26-M29).

**M31 — ✅ Completata (17 ago 2026) — Form e Impostazioni adattivi**
- Mockup di confronto (prima/dopo) discusso e approvato da Mario: proposta
  iniziale con Regole Merchant in griglia (come Budget M29) — **scartata**
  da Mario, "più semplice da implementare e comode da usare" con la sola
  centratura ovunque, nessuna griglia.
- **Fatto**: `ContentWidthLimiter` aggiunto a tutte le pagine rimaste senza
  (nessuna ristrutturazione, solo centratura su finestra larga):
  `add_transaction_page.dart`, `settings_page.dart`,
  `categories_manage_page.dart`, `merchant_rules_page.dart`,
  `export_page.dart`, `import_page.dart`, `sync_page.dart`,
  `gemini_page.dart`, `theme_page.dart`, `admin_page.dart`,
  `statement_import_page.dart`. Larghezza massima 640 (default, form/liste
  semplici) tranne Admin e Import estratto conto (900: righe più dense —
  checkbox, importo, sottocategoria, azioni — stesso motivo per cui Budget
  M29 aveva bisogno di più spazio nelle celle di griglia).
- **Fix incluso, non solo M31**: in Storico (M30) la barra di ricerca non
  era centrata come la lista sottostante — `ContentWidthLimiter` avvolgeva
  solo la lista, non l'intero body. Corretto insieme (avvolge ora
  ricerca + lista in un colpo solo).
- **Richiesta aggiuntiva di Mario**: icona "i" (info) in AppBar in Regole di
  classificazione, apre un bottom sheet (`showRuleHelpSheet`,
  `merchant_rules_page.dart`) che spiega come scrivere un pattern —
  matching case-insensitive che cerca il pattern ovunque nel testo (non
  serve `^`/`$`), simboli di base (`.`, `.*`, `A|B`, escape con `\`),
  priorità (più alta vince a parità di match) e che un pattern non valido
  non dà errore, semplicemente non classifica mai nulla — stessa logica
  reale di `rule_matcher_service.dart`, descritta perché chi scrive una
  regola sappia cosa aspettarsi.
- `flutter analyze` pulito, **169/169 test invariati** (nessuna logica di
  business toccata, solo layout/presentazione + un testo informativo).

**M33 — ✅ Completata (17 ago 2026) — Conteggio e media per categoria/
sottocategoria in Dashboard**
*(richiesta da Mario dopo una domanda aperta "cosa proponi di
implementare o migliorare?")*
- Problema/richiesta: nella torta e nelle barre sottocategoria della
  Dashboard si vede solo l'importo totale — utile sapere anche **quante
  volte** è ricorsa una spesa in quella categoria/sottocategoria e il suo
  **valore medio**. Vincolo esplicito di Mario, con esempio concreto: una
  spesa di 50€ con un rimborso collegato di 25€ deve contare come **1**
  occorrenza con media **25€** (l'importo netto), non 2 occorrenze né una
  media che pesa il rimborso come spesa a sé (es. non `(50-25)/2`).
- **Fatto**: la logica esisteva già in parte — `netExpense` su
  `TransactionEntity` (spesa normale = +importo, rimborso = -importo) è
  già usata per sommare gli importi per categoria/sottocategoria in
  `dashboard_providers.dart`, quindi il netting del rimborso era già
  corretto. Serviva solo aggiungere il **conteggio**: un nuovo contatore
  che si incrementa solo per transazioni con `isRefund == false` (un
  rimborso non è mai una nuova occorrenza, sempre e solo la rettifica di
  una spesa già contata nella stessa categoria) — verificato che
  combaci esattamente con l'esempio di Mario (conteggio 1, media 25€).
  - `CategorySlice`/`SubcategorySlice` (`dashboard_providers.dart`): nuovo
    campo `count` + getter `average` (`amount / count`, 0 se count è 0 —
    mai il caso per una fetta effettivamente mostrata, dato che il filtro
    esistente "solo importi > 0" implica almeno una spesa non-rimborso).
  - **Refactor di supporto**: la logica di aggregazione (prima una
    closure anonima dentro il provider, non testabile senza Riverpod/
    Drift) è stata estratta in `buildDashboardData(...)`, funzione pura a
    livello di file — permette un test diretto senza dover simulare
    stream/DB. Il provider resta un sottile wrapper che chiama questa
    funzione. Nessun cambio di comportamento, solo spostamento di codice.
  - `category_donut.dart`/`subcategory_bars.dart`: seconda riga sotto il
    nome (si allinea da sola con o senza icona, grazie a un `Column`
    dentro l'`Expanded` invece di un `Text` semplice) con un badge
    arrotondato col conteggio (`CountBadge`, nuovo widget dedicato — Mario
    ha chiesto esplicitamente un "box" invece di un testo tipo "12
    transazioni") + "media X €" attenuato accanto. Riga mostrata solo se
    `count > 0`. `crossAxisAlignment: start` sulla riga esterna: senza,
    pallino/percentuale/importo si sarebbero centrati sull'intero blocco a
    due righe invece di restare allineati alla prima (il nome).
  - Applicato **sia** alla torta per categoria **sia** alle barre per
    sottocategoria (scelta esplicita di Mario tra le due opzioni proposte:
    stessa logica, nessuno sforzo aggiuntivo a farlo su entrambi i
    livelli).
  - **Nuovo test dedicato** `test/dashboard_data_test.dart` (9 test):
    l'esempio esatto di Mario (50€ spesa + 25€ rimborso stessa categoria →
    1/25€), più occorrenze senza rimborso, netting a livello di
    sottocategoria, inclusione/esclusione delle straordinarie
    (`includeExtra`), categoria con solo un rimborso e nessuna spesa reale
    (non deve comparire), filtro mese, e il caso vuoto (nessuna divisione
    per zero). Prima di questo M33, `dashboard_providers.dart` non aveva
    alcun test dedicato (aggregazione intrecciata al provider Riverpod) —
    il refactor in funzione pura sopra è ciò che ha reso possibile
    scriverli.
  - `flutter analyze` pulito, **178/178 test** (169 + 9 nuovi).

**M34 — ✅ Completata (17 ago 2026) — Doppio click su categoria/
sottocategoria apre lo Storico filtrato**
- Richiesta: doppio click su una categoria o sottocategoria in Dashboard
  deve portare allo Storico con la ricerca testuale già impostata sul nome
  cliccato.
- **Fatto**:
  - `HistoryPage` accetta un `initialQuery` opzionale che precompila
    `_searchController`/`_query` (resta comunque modificabile/cancellabile
    come una ricerca digitata a mano). Route `/history`
    (`app_router.dart`) legge `state.extra as String?` e lo passa.
  - `CategoryDonut`/`SubcategoryBars`: nuovo callback `onOpenHistory`,
    agganciato con `InkWell(onDoubleTap: ...)` sulle righe di legenda
    (categoria) e sulle righe delle barre (sottocategoria) — non sulle
    fette della torta stesse (nessun testo lì, l'informazione "nome
    cliccato" vive solo nelle righe). `dashboard_page.dart` fa da
    tramite verso `context.push('/history', extra: name)` (nessuna delle
    due card conosce go_router direttamente, restano presentazionali).
  - **Compromesso da sapere**: sulla legenda categoria, che aveva già un
    `onTap` (seleziona la categoria per il dettaglio sottocategorie),
    aggiungere `onDoubleTap` sullo stesso `InkWell` introduce il ritardo
    standard di Flutter (~300ms) prima che scatti il singolo click, perché
    il framework deve aspettare per capire se arriva un secondo tap. Sulle
    barre sottocategoria, che non avevano nessun tap esistente, non c'è
    questo effetto collaterale (nessun altro riconoscitore con cui
    competere sulla stessa riga).
  - `flutter analyze` pulito, **178/178 test invariati** (nessuna logica
    di business nuova: solo un parametro passato a cascata e un
    `onDoubleTap` su widget di presentazione).
- **Revisione layout (17 ago 2026, richiesta da Mario)**: colonna sinistra
  ora solo la torta; colonna destra andamento 12 mesi sopra, barre
  sottocategoria sotto (prima la sottocategoria era affiancata alla torta
  a sinistra) — v. nota aggiunta a M28 sopra per il dettaglio.
- **Numeri senza decimali (17 ago 2026, richiesta di Mario)**: tutti gli
  importi mostrati in Dashboard (torta, legenda, barre sottocategoria,
  media, le 3 card totali, tooltip dell'andamento 12 mesi) ora arrotondati
  senza cifre decimali — nuovo `AppFormatters.currencyRounded`/
  `signedCurrencyRounded` (`decimalDigits: 0`). **Esteso su richiesta
  esplicita di Mario anche alla card "Riepilogo annuale" del Budget**
  (`annual_summary_card.dart`, M29): obiettivo di risparmio, le due
  mini-tabelle Effettive/Previsione (reddito/spese/risparmio), quanto si
  può spendere al mese e il margine — stesso `currencyRounded`/
  `signedCurrencyRounded`. **Non** toccato il dialog di modifica
  dell'obiettivo (`_editGoal`): è un campo di input per un importo
  preciso, non una cifra mostrata, resta a 2 decimali. Usato **solo** in
  questi due punti: Home, Storico e il resto del Budget continuano a
  mostrare i centesimi come prima, non è un cambio globale del formatter
  valuta esistente.

**M35 — ✅ Completata (17 ago 2026) — Rimozione tabella Merchants**
*(valutata l'implementazione completa vs la rimozione con Mario, dopo una
domanda aperta "cosa manca?" sulle possibili migliorie)*
- **Indagine, prima di decidere**: la tabella `Merchants` (schema pronto
  con `syncId` fin dall'inizio, pensata per un futuro campo "Negozio" con
  autocompletamento in Nuova Operazione, categoria di default per negozio,
  e uno stat "Top negozi" in Dashboard) non è mai stata collegata a un
  DAO/repository/mapper/UI in circa un anno di sviluppo — sempre 0 righe.
  Il flusso scontrini (M3) ha preso un'altra strada, che funziona bene: il
  nome negozio finisce come testo libero nella Nota, categorizzato
  automaticamente da **Regole Merchant** (regex sul testo) — mai toccando
  la tabella Merchants. `merchantId` su Transactions è sempre rimasto
  `null` ovunque (anche scansione scontrini e import estratto conto non lo
  popolano). Non collegata nemmeno alla sync Turso (avrebbe richiesto
  supporto nuovo di zecca: `sync_merchants`, push/pull, traduzione FK).
- **Decisione**: costo (nuovo DAO/repository/mapper/provider, campo
  "Negozio" con autocompletamento, collegamento anche a scontrini/import
  estratto conto per non lasciare "Top negozi" parziale, supporto sync
  nuovo, nessun backfill sensato per le transazioni storiche) non
  giustificato dal beneficio, con Regole Merchant + ricerca full-text su
  Nota già a coprire categorizzazione e ricerca. Scelta: **rimozione**,
  non abbandono silenzioso (la tabella/colonna non costavano nulla a
  restare, ma un `DROP` esplicito chiude la questione invece di lasciarla
  a metà per sempre).
- **Fatto**: schema v8. Rimossi `merchants_table.dart`, il campo
  `merchantId` da `Transactions` (tabelle Drift), `TransactionEntity`,
  `transaction_mapper.dart`, `add_transaction_page.dart`; rimosso anche il
  parametro `merchantQuery` mai realmente passato da nessun chiamante
  (`TransactionRepository.search`, `SearchTransactionsParams`) — stessa
  pulizia, stesso piano abbandonato.
  - **Niente `DROP COLUMN` diretto** per `merchantId`: SQLite non permette
    di eliminare una colonna soggetta a un vincolo FOREIGN KEY (referenziava
    `Merchants.id`). Usato invece `Migrator.alterTable(TableMigration(...))`
    di Drift, che ricrea la tabella secondo la definizione Dart corrente
    (già senza `merchantId`) copiando le righe esistenti per nome colonna.
    Poi `m.deleteTable('merchants')` per la tabella stessa. Guardie di
    idempotenza sullo stesso principio di `_columnExists` (M17): nuovo
    `_tableExists`, entrambi gli step in `onUpgrade` controllano prima di
    agire, per una migrazione interrotta a metà.
  - **Test nuovi** in `test/app_database_migration_test.dart` (2 test): un
    DB v7 reale ricostruito con Merchants popolata + una transazione con
    `merchantId` valorizzato → riaperto con lo schema corrente, verifica
    che entrambe spariscano senza eccezioni e senza perdere le altre
    colonne della transazione; più un test di idempotenza (riapertura
    ripetuta). Il test esistente per il bug M17 aggiornato (asseriva
    `user_version` 7, ora 8 con lo schema bump).
  - **Verificato anche sul database vero di Mario** (backup preventivo
    `finance_app.sqlite.backup-2026-08-17-pre-m35-merchants-removal`):
    migrazione applicata su una copia prima di toccare il file vero (0
    righe in `merchants`, 0 transazioni con `merchantId` valorizzato,
    confermato — coerente con l'indagine), poi sull'app reale via build
    Windows: 1908 transazioni invariate, `merchant_id`/tabella `merchants`
    spariti, `PRAGMA integrity_check` → `ok`.
  - `flutter analyze` pulito, **180/180 test** (178 + 2 nuovi).

**M36 — ✅ Completata — Storico: menu azioni a comparsa (bug leggibilità mobile)**
*(segnalato da Mario dopo aver aperto l'app sul secondo dispositivo, 18 ago
2026)*
- **Bug reale**: su schermo stretto (telefono) la sottocategoria sotto la
  Nota (aggiunta in M30) risultava illeggibile/senza spazio. Causa: il
  `trailing` di `_HistoryTile` (`history_page.dart`) poteva contenere fino a
  3 `IconButton` (rimborsa, rimborso con divisore, elimina) più l'importo,
  tutti in una `Row` a larghezza libera — su schermo stretto occupava gran
  parte della card, lasciando troppo poco spazio a `title`/`subtitle`. Su
  desktop (finestra larga) il problema non si vedeva, da qui la scoperta
  solo ora aprendo l'app sul telefono.
- **Fix, in due passaggi nella stessa sessione**:
  1. Le azioni (spesa collegata, rimborsa, rimborso con divisore, elimina)
     raccolte in un unico `PopupMenuButton` (icona "⋮"), scelto da Mario tra
     due opzioni proposte (l'alternativa era la card su due righe, v. punto
     2). Verificato a ~400px di larghezza finestra: migliora, ma Mario
     l'ha segnalato ancora insufficiente ("è ancora troppo tagliato tutto")
     — causa strutturale non ancora risolta dal solo menu: in un `ListTile`,
     `trailing` sottrae larghezza condivisa sia a `title` sia a `subtitle`,
     quindi la sottocategoria in `subtitle` restava comunque schiacciata
     dallo stesso `trailing` (importo + "⋮"), indipendentemente da quante
     icone contenga.
  2. **Card ricostruita su due righe indipendenti** (non più `ListTile`):
     `Card > InkWell > Padding > Column`. Riga 1 = icona categoria + data +
     Nota (`Expanded`, ellissi se serve) + badge rimborsi collegati +
     importo + `PopupMenuButton`. Riga 2 = sottocategoria/tag, indentata
     sotto la Nota (`Padding(left: 44)`), larghezza piena della card, MAI
     condivisa con l'importo. Questo è il fix che risolve davvero il
     problema: la riga 2 non dipende più da quanto spazio occupa la riga 1.
  3. Su proposta di Mario, la data si sposta **sotto l'icona categoria**
     invece che accanto (`Column` icona+data invece di stare in `Row` con
     la Nota): il blocco icona+data sulla riga 1 resta largo solo quanto
     l'icona, liberando altro spazio alla Nota prima del troncamento.
- **Verificato**: `flutter analyze` pulito, 180/180 test invariati (nessuna
  copertura di test dedicata alla sola disposizione grafica della card),
  più verifica visiva con build Windows reale, finestra ridotta fino a
  360px (paragonabile alla larghezza di un telefono): nota+importo+menu
  sulla riga 1, sottocategoria/tag per intero sulla riga 2 anche nei casi
  più lunghi osservati ("Alimentari in Viaggio · Rimborso").

**M37 — ✅ Completata — Distribuzione Windows via GitHub Releases (zip portabile)**
*(richiesto da Mario, 18 ago 2026)*
- Problema: l'unico modo per aggiornare l'app Windows su un dispositivo era
  ricompilarla da sorgente (`flutter build windows --release`) — pratico per
  sviluppo, scomodo per uso quotidiano. Richiesta: un modo semplice per
  scaricare/aggiornare l'app già pronta, "hostabile su internet" (proposto
  inizialmente Google Drive).
- Scelte (con Mario, tra le opzioni proposte):
  - **Hosting: GitHub Releases**, non Google Drive — Drive mostra un avviso
    "impossibile eseguire la scansione antivirus" sui file eseguibili/zip
    che complica il download diretto, e non tiene uno storico versioni
    ordinato. Il repo è già su GitHub, nessun servizio nuovo da configurare.
  - **Pacchetto: zip portabile**, non un vero installer (scartata
    l'alternativa Inno Setup): la build Windows release di Flutter non
    richiede installazione (nessuna scrittura di registro), comprimere la
    cartella `build/windows/x64/runner/Release/` basta — zero strumenti
    nuovi da installare sul PC di build, stesso principio "solo l'essenziale"
    già seguito altrove nel progetto.
  - **Una sola release "rolling"** (tag `windows-latest`), non una release
    versionata per ogni build — stesso principio già in uso per l'APK
    Android (`android-build.yml`: sempre l'ultimo artifact, nessuno storico
    da mantenere). Aggiornare significa sostituire l'asset zip mantenendo
    stesso tag/nome file: il link di download resta fisso,
    `https://github.com/dukan94/segnaspese/releases/download/windows-latest/Tally-Windows.zip`.
  - **Creazione manuale della release**, non automatizzata da un workflow
    Actions: `gh` CLI non è installata su questo PC (dispositivo aziendale,
    stesso motivo per cui manca l'Android SDK) e non si è voluto
    installarla solo per questo. Mario pubblica la release dall'interfaccia
    web di GitHub (drag&drop dello zip), nessun nuovo strumento coinvolto.
    Un'automazione futura (workflow `workflow_dispatch` che builda e
    pubblica la release, sul modello di `android-build.yml`) resta
    un'estensione possibile ma non richiesta ora.
- **Verificato**: build Windows release (già aggiornata a M36) compressa in
  zip (~15 MB) con `Compress-Archive` (PowerShell, nessun tool nuovo), copiata
  in Download per comodità di upload. Release pubblicata da Mario via
  browser, tag `windows-latest` confermato sul remoto (`git ls-remote
  --tags`). Repo privato: non verificabile con `WebFetch` (non autenticato),
  confermato invece da Mario col download diretto del link (~15 MB,
  scaricato con successo).
- **Per i prossimi aggiornamenti**: rifare `flutter build windows --release`
  → `Compress-Archive` → sostituire l'asset sulla release `windows-latest`
  esistente (stesso nome file `Tally-Windows.zip`) mantenendo il link fisso.

### Processo per nuove milestone (da qui in avanti)

Deciso con Mario il 16 ago 2026, per non perdere il filo come è successo con
il lavoro "post-M8" (fatto bene, ma poco visibile perché non numerato):
**ogni modifica non banale** (nuova feature, estensione a una milestone
esistente, fix strutturale — non un typo o una correzione cosmetica) segue
sempre questi passi, in ordine:

1. **Categorizza**: è una nuova milestone (M18, M19, ...), un'estensione di
   una milestone già chiusa (es. "Estensione post-M15"), o un fix
   abbastanza piccolo da meritare solo una riga in un'"insidia" esistente in
   CLAUDE.md? La differenza è la portata: una nuova pagina/flusso utente è
   quasi sempre una milestone; un bug fix locale a un meccanismo già
   documentato è quasi sempre solo una nota.
2. **Documenta PRIMA di scrivere codice**: aggiungi qui in sezione 6 la voce
   "M<N> — <titolo>" con lo stato **🔧 Proposta** e una descrizione breve di
   problema + approccio previsto. Aspetta l'ok esplicito di Mario prima di
   passare al passo 3 (il metodo di lavoro concordato da sempre: design
   approvato prima di scrivere codice — qui semplicemente lo mettiamo per
   iscritto invece che solo a voce).
3. **Sviluppa**: implementa, `flutter analyze` + `flutter test` (rigenera
   `build_runner` se serve), poi aggiorna la voce a **✅ Completata** con
   cosa è stato fatto davvero (se diverso dal piano iniziale, come già
   successo per M3/scontrini o M6/export).
4. **Propaga lo stato**: aggiorna `README.md` (tabella milestone) e
   `CLAUDE.md` ("Stato attuale") per puntare alla nuova voce — stesso
   principio già in uso, ora esplicito anche qui.

---

## Note tecniche aggiuntive

- **Librerie effettivamente usate (tutte gratuite):** `drift` + `sqlite3_flutter_libs` (DB locale), `http` (client Turso HTTP e Gemini — niente `libsql_dart`, v. sezione 1), `googleapis` + `googleapis_auth` (bridge temporaneo Google Sheets via service account, niente `google_sign_in`: non supporta Windows desktop), `flutter_secure_storage` (credenziali Turso + API key Gemini + chiave service account Sheets), `google_mlkit_text_recognition` + `camera`/`image_picker` (scontrini), `fl_chart` (dashboard), `go_router` (routing), `flutter_riverpod` (state/DI), `csv` + `file_picker` (import/export), `intl`, `uuid`, `collection`.
- **Piattaforme generate:** Windows desktop e Android. macOS/iOS/Linux non generate (aggiungibili con `flutter create --platforms=<piattaforma> .` se servisse in futuro).
- **Turso — piano Free:** sufficiente per uso personale; nessuna carta di credito richiesta per l'attivazione.
- **Performance inserimento:** categoria/sottocategoria più usate vengono precaricate come default nel form manuale, riducendo a 3-4 tap il tempo di inserimento.

---

**Stato attuale (17 ago 2026):** tutte le milestone **M0-M35 completate**,
nessuna proposta aperta al momento (v. sezione 6 per il dettaglio di
ciascuna). M9-M24: Admin e manutenzione dati, icona/splash "Tally",
robustezza doppioni transazioni, build Android release, blocco doppioni
categoria + strumento "Unisci con...", ricorrenze a numero di occorrenze
finito, import estratto conto bancario, rifiniture ricerca/dashboard/CI,
migrazione schema locale idempotente, fix sicurezza API key Gemini,
gestione errori cancellazione transazione, verifica `sqlite3_flutter_libs`,
timeout Google Sheets, isolamento errori avvio, copertura test logica
critica, aggiornamento dipendenze. M25: rimborso con divisore (quota di una
spesa condivisa). M26-M31: refactor desktop-adattivo (densità,
`NavigationRail`, `ContentWidthLimiter`, tutte le pagine
riorganizzate/centrate su finestra larga, icona info Regole di
classificazione — v. sezione dedicata in CLAUDE.md). M32: sync Turso
immediata su inserimento/modifica/cancellazione transazione, oltre al
timer ogni 5 minuti. M33: conteggio e media per categoria/sottocategoria
in Dashboard, al netto dei rimborsi. M34: doppio click su
categoria/sottocategoria in Dashboard apre lo Storico filtrato, più
riordino colonne Dashboard e numeri senza decimali (Dashboard + Riepilogo
annuale). M35: rimossa la tabella `Merchants` (mai collegata a un
DAO/UI/sync in un anno di sviluppo, sempre 0 righe) e la colonna
`merchantId` da Transactions — valutata l'implementazione completa vs la
rimozione, scelta la rimozione. Schema DB Drift alla **versione 8**, ora
su **`sqlite3` 3.x nativo** (M24: `sqlite3_flutter_libs` rimosso, v.
sezione dedicata in CLAUDE.md — non reintrodurlo). **CI attiva**
(`.github/workflows/ci.yml`): `flutter analyze` + `flutter test` su ogni
push e PR (con rigenerazione del codice; `android-build.yml` invece solo
su richiesta manuale da M35/17 ago 2026, v. CLAUDE.md — quota minuti
Actions/mese esaurita). Test: **27 file, 180 test** in `test/` (parser
CSV, receipt parser, rule matcher, duplicate finder, motore di sync Turso
(incluso rientranza `syncNow()`, verifica remota puntuale e migrazione
schema remoto), repair sottocategorie orfane, widget animati, DAO
ricorrenze/categorie/budget/transazioni (incluso hard delete/purge,
riemissione live del riordino, unione categorie/sottocategorie, numero di
occorrenze finito), formatter e servizio Google Sheets (header matching),
`SafeTransactionDeletionService`, parser estratto conto BancoPosta e
duplicate matcher, migrazione locale idempotente (M17) **+ rimozione
tabella Merchants (M35)**, servizio Gemini incluso il regression test di
sicurezza M18, seed runner, dedupe tassonomia, client HTTP Turso con
encoding/decoding reale (M23), export CSV (M24), rimborso con divisore
(M25), conteggio/media Dashboard (M33, `dashboard_data_test.dart`) + 1
smoke widget test). Repository impl e usecase restano senza test dedicati:
delega pura, nessuna logica propria. Da qui in avanti, ogni nuova modifica
non banale segue il processo descritto in fondo alla sezione 6 (categorizza
→ documenta come milestone qui, in attesa di ok → sviluppa → propaga lo
stato a README/CLAUDE.md).

> NOTA PIATTAFORME: generate **Windows** (`windows/`) e **Android**
> (`android/`, con `applicationId` dedicato, permesso INTERNET e CI). Per
> aggiungere altre piattaforme: `flutter create --platforms=<piattaforma> .`,
> poi verificare permessi/`minSdk` per `google_mlkit_text_recognition` e
> `camera` (≥ 21).

> NOTA BUILD: modifiche allo schema Drift o ai provider Riverpod richiedono
> `dart run build_runner build --delete-conflicting-outputs`. Lo schema DB è
> alla versione **8** (v. `AppDatabase.schemaVersion` in `app_database.dart`).
> Ogni `addColumn`/ALTER TABLE in `onUpgrade` deve controllare che la colonna
> non esista già (`_columnExists`, v. sezione 6 M17) prima di aggiungerla:
> una migrazione interrotta a metà può lasciare la colonna già presente
> fisicamente con la versione vecchia ancora registrata. Per eliminare una
> colonna soggetta a un vincolo FOREIGN KEY, `DROP COLUMN` diretto non è
> possibile: serve `TableMigration` (v. sezione 6 M35), che ricrea la
> tabella secondo la definizione Dart corrente copiando le righe per nome
> colonna — stessa idempotenza garantita da una guardia `_tableExists`
> prima di un `deleteTable`.
