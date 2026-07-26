# Progettazione Completa — App Finanze Personali (Flutter)

> Documento di design da approvare prima di procedere con l'implementazione del codice.

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

### Sync multi-dispositivo (Turso)

Pattern **offline-first con embedded replica**:

- Ogni dispositivo (telefono/PC) mantiene un file **SQLite locale** (letto/scritto da Drift come sempre, nessuna latenza percepita dall'utente).
- In background, un `SyncService` sincronizza in modo bidirezionale il file locale con il database remoto su **Turso** (libSQL), usando la modalità *embedded replica* del client libSQL.
- L'app resta **pienamente funzionante offline**: scrivi in locale, la sync avviene appena c'è connessione.
- **Risoluzione conflitti**: last-write-wins basato su un campo `updatedAt` presente su ogni riga (vedi schema aggiornato sotto). Sufficiente per un uso personale mono-utente su più dispositivi (raramente scrivi sullo stesso record da due device nello stesso istante).
- Il layer `domain/` non cambia: i repository restano le stesse interfacce astratte già progettate. Solo `data/services/sync_service.dart` è nuovo.
- **Costo:** piano Free di Turso, ampiamente sufficiente per i volumi di un'app di finanza personale (v. discussione precedente).

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

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router + tema
│
├── core/
│   ├── di/                           # provider globali (db instance, services)
│   ├── theme/                        # ColorScheme M3 light/dark, typography
│   ├── router/                       # go_router config
│   ├── utils/                        # formatters (valuta, date), extensions
│   ├── constants/                    # icone categorie default, regex patterns
│   └── errors/                       # Failure, Result<T> / Either
│
├── domain/
│   ├── entities/
│   │   ├── transaction_entity.dart
│   │   ├── category_entity.dart
│   │   ├── subcategory_entity.dart
│   │   ├── merchant_entity.dart
│   │   ├── merchant_rule_entity.dart
│   │   ├── budget_entity.dart
│   │   └── recurring_transaction_entity.dart
│   ├── repositories/                 # interfacce astratte
│   │   ├── transaction_repository.dart
│   │   ├── category_repository.dart
│   │   ├── merchant_repository.dart
│   │   ├── budget_repository.dart
│   │   ├── recurring_repository.dart
│   │   └── import_export_repository.dart
│   └── usecases/
│       ├── transaction/
│       │   ├── add_transaction.dart
│       │   ├── delete_transaction.dart
│       │   └── search_transactions.dart
│       ├── receipt/
│       │   ├── scan_receipt.dart
│       │   ├── classify_merchant.dart
│       │   └── learn_new_rule.dart
│       ├── budget/
│       │   ├── compute_budget_balance.dart
│       │   └── compute_real_balance.dart
│       ├── recurring/
│       │   └── generate_due_recurring_transactions.dart
│       └── stats/
│           └── build_dashboard_stats.dart
│
├── data/
│   ├── local/
│   │   ├── database/
│   │   │   ├── app_database.dart     # Drift @DriftDatabase
│   │   │   ├── tables/
│   │   │   │   ├── transactions_table.dart
│   │   │   │   ├── categories_table.dart
│   │   │   │   ├── subcategories_table.dart
│   │   │   │   ├── merchants_table.dart
│   │   │   │   ├── merchant_rules_table.dart
│   │   │   │   ├── budgets_table.dart
│   │   │   │   ├── recurring_table.dart
│   │   │   │   └── settings_table.dart
│   │   │   ├── daos/
│   │   │   │   ├── transaction_dao.dart
│   │   │   │   ├── category_dao.dart
│   │   │   │   ├── merchant_dao.dart
│   │   │   │   ├── budget_dao.dart
│   │   │   │   └── recurring_dao.dart
│   │   │   └── migrations/
│   │   └── seed/                     # categorie/regole di default al primo avvio
│   ├── services/
│   │   ├── ocr_service.dart          # wrapper Google ML Kit Text Recognition
│   │   ├── receipt_parser_service.dart  # estrae negozio + totale dal testo OCR
│   │   ├── rule_matcher_service.dart    # applica regex delle MerchantRules
│   │   └── excel_service.dart        # import/export xlsx + csv (syncfusion/excel pkg free)
│   ├── mappers/                      # Drift row ↔ Domain entity
│   └── repositories_impl/
│       ├── transaction_repository_impl.dart
│       ├── category_repository_impl.dart
│       ├── merchant_repository_impl.dart
│       ├── budget_repository_impl.dart
│       ├── recurring_repository_impl.dart
│       └── import_export_repository_impl.dart
│
└── presentation/
    ├── home/
    │   ├── home_page.dart
    │   ├── widgets/                  # balance_card, quick_stats, recent_list
    │   └── home_providers.dart
    ├── transaction/
    │   ├── add_transaction_page.dart # inserimento manuale rapido
    │   ├── transaction_detail_page.dart
    │   └── widgets/                  # amount_keypad, category_picker
    ├── scanner/
    │   ├── receipt_scan_page.dart    # camera + preview
    │   ├── receipt_review_page.dart  # conferma categoria/importo proposti
    │   └── widgets/
    ├── dashboard/
    │   ├── dashboard_page.dart
    │   ├── widgets/                  # charts wrappers (fl_chart)
    │   └── dashboard_providers.dart
    ├── budget/
    │   ├── budget_page.dart
    │   └── budget_edit_sheet.dart
    ├── recurring/
    │   ├── recurring_list_page.dart
    │   └── recurring_edit_page.dart
    ├── search/
    │   └── search_page.dart
    ├── settings/
    │   ├── settings_page.dart
    │   ├── categories_manage_page.dart
    │   ├── merchant_rules_page.dart  # tabella regole modificabile
    │   └── import_export_page.dart
    └── shared_widgets/                # bottom nav, FAB, empty states
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
| amount | real | sempre positivo, il segno lo dà `type` |
| type | enum(income, expense) | |
| categoryId | int (FK) | |
| subCategoryId | int (FK, nullable) | |
| merchantId | int (FK, nullable) | |
| note | text (nullable) | |
| receiptImagePath | text (nullable) | path locale foto scontrino |
| recurringId | int (FK, nullable) | valorizzato se generata da ricorrenza |
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

### Campi di sync (aggiunti a tutte le tabelle sopra)

Per supportare la sincronizzazione multi-dispositivo via Turso, ogni tabella riceve inoltre:

| Campo | Tipo | Note |
|---|---|---|
| updatedAt | dateTime | usato per il conflict-resolution last-write-wins |
| isDeleted | bool | soft delete, necessario perché le cancellazioni vanno propagate in sync |

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

**M3 — OCR e Scontrini**
- Integrazione Google ML Kit Text Recognition (offline)
- `receipt_parser_service` per estrazione negozio + totale
- Tabella MerchantRules + `rule_matcher_service` (regex)
- Flusso apprendimento: negozio sconosciuto → chiedi categoria → crea regola
- Schermata gestione regole in Impostazioni

**M4 — Dashboard e Statistiche**
- Integrazione fl_chart: andamento mensile/annuale, per categoria/sottocategoria, top negozi
- Filtri (mese, anno, categoria, sottocategoria)

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

**M7 — Sync multi-dispositivo (Turso)**
- Setup database Turso (piano Free) + embedded replica libSQL
- `SyncService`: push/pull bidirezionale, gestione `updatedAt`/`isDeleted`
- Indicatore di stato sync in UI (es. icona in Home: sincronizzato / in attesa / offline)
- Build desktop (Windows/macOS/Linux) oltre a mobile, per l'accesso da PC

**M8 — Rifinitura**
- Animazioni, dark mode completo, empty states, gestione errori
- Test unitari su UseCase e repository, test widget sulle schermate chiave

---

## Note tecniche aggiuntive

- **Librerie gratuite proposte:** `drift`, `sqlite3_flutter_libs`, `libsql_dart` (client Turso/embedded replica), `google_mlkit_text_recognition`, `fl_chart`, `go_router`, `flutter_riverpod` + `riverpod_generator`, `excel` (pacchetto pub.dev per xlsx, gratuito), `image_picker`/`camera`, `intl` per formattazione valuta/data.
- **Piattaforme target:** Android, iOS, Windows, macOS, Linux — Flutter compila nativamente su tutte queste piattaforme da un'unica codebase, senza costi aggiuntivi.
- **Turso — piano Free:** sufficiente per uso personale (v. discussione su costi); nessuna carta di credito richiesta per l'attivazione.
- **Performance inserimento:** categoria/sottocategoria più usate vengono precaricate come default nel form manuale, riducendo a 3-4 tap il tempo di inserimento.

---

**Stato attuale (26 lug 2026):** completate M0, M1, M2, M4, M5 e M6. **M3
parziale** (parser scontrini, regole merchant e flusso di apprendimento
presenti; manca l'acquisizione reale da fotocamera + OCR ML Kit). Extra già
implementati oltre la roadmap: storico movimenti, import/export CSV, rimborsi
come uscite con collegamento alla spesa originale (`refundOfId`), navigazione a
4 voci con hub "Altro", filtro mese in Dashboard, mesi passati non impostabili
nel Budget.

**Prossimi passi:** M3 (OCR reale — richiede un dispositivo Android/mobile),
poi M7 (sync Turso) e M8 (test automatici).

> NOTA PIATTAFORME: al momento è generata **solo la piattaforma Windows**
> (`windows/`). Per lo sviluppo mobile va aggiunta la piattaforma Android con
> `flutter create --platforms=android .`; poi vanno configurati i permessi
> fotocamera nel `AndroidManifest.xml` e verificato il `minSdk` per
> `google_mlkit_text_recognition` e `camera` (≥ 21).

> NOTA BUILD: modifiche allo schema Drift o ai provider Riverpod richiedono
> `dart run build_runner build --delete-conflicting-outputs`. L'ultima
> migrazione DB è la v4 (`refundOfId`).
