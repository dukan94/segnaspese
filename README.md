# Tally — Monitoraggio Spese con Scansione Scontrini

App multipiattaforma (Flutter) per **tenere sotto controllo le spese personali**:
scansiona lo scontrino, riconosce automaticamente le voci di spesa, le
categorizza e le salva in un database locale, con dashboard, budget e
movimenti ricorrenti. Nata come app Android, gira anche come **applicazione
desktop Windows** grazie a Flutter.

## Funzionalità principali

- **Scansione scontrini con AI** — su mobile la foto viene letta da Google
  Gemini (API cloud gratuita, API key personale) per estrarre negozio/
  importo/data; se la key non è configurata o la chiamata cloud fallisce, si
  ricade sull'OCR offline (Google ML Kit) + regole regex. Regole di
  classificazione automatica (con apprendimento) per assegnare la categoria
  giusta al negozio.
- **Categorizzazione** — categorie e sottocategorie personalizzabili (con
  riordino drag & drop), regole per merchant. Nomi duplicati bloccati in UI;
  un'azione "Unisci con..." permette di consolidare due categorie/
  sottocategorie doppione spostando transazioni/regole/budget/ricorrenze
  sulla destinazione prima di eliminare la sorgente.
- **Inserimento manuale** — schermata "Nuova Operazione" con tastierino rapido
  per aggiungere spese a mano; al salvataggio controlla sul database se
  esiste già una spesa con stessa data, categoria e importo (probabile
  doppione, es. scontrino inserito due volte) e in tal caso avvisa con un
  link alla spesa di riferimento, chiedendo conferma prima di procedere.
- **Dashboard** — grafici e riepiloghi (andamento mensile, per categoria/
  sottocategoria, totali annuali) per monitorare l'andamento delle spese.
- **Budget** — piano annuale con budget totale mese per mese, suddiviso tra
  categorie.
- **Movimenti ricorrenti** — gestione di spese/entrate che si ripetono, con
  generazione automatica delle occorrenze dovute all'avvio dell'app.
  Opzionalmente a numero di occorrenze finito (es. "12 rate"): raggiunto il
  numero impostato si mette in pausa da sola.
- **Rimborsi collegati** — un rimborso può essere agganciato alla spesa
  originale (dallo Storico o dal form di modifica).
- **Ricerca e import/export CSV** — ricerca full-text sui movimenti,
  import/export CSV round-trip (compatibile con Excel).
- **Import estratto conto bancario** — importa i movimenti da un file Excel
  esportato dalla banca (Impostazioni, un parser per banca, primo supporto
  per Poste Italiane/BancoPosta). Ogni riga arriva con una categoria già
  proposta dalle stesse regole di classificazione usate per gli scontrini
  (modificabile), ed è segnalata se sembra un doppione di una transazione già
  presente in locale (esclusa di default dalla selezione, ma modificabile) —
  revisione riga per riga prima di confermare il salvataggio.
- **Sync multi-dispositivo** — sincronizzazione offline-first tra dispositivi
  via Turso (HTTP), con alert visibile in Home se non configurata o in
  errore, oltre alla build desktop dedicata. Pensata per più dispositivi
  attivi insieme (es. 2 PC Windows + 1 Android): le eliminazioni definitive
  vengono confermate direttamente dal server prima di essere fisiche, per
  evitare che un movimento cancellato ricompaia da un altro dispositivo.

## Stack tecnologico

- **Flutter / Dart** — UI multipiattaforma (Android, Windows desktop, ecc.)
- **Clean Architecture** — separazione in `core` / `domain` / `data` / `presentation`
- **Drift** — database locale relazionale con codice generato
- **Riverpod** — state management e dependency injection
- **go_router** — navigazione dichiarativa
- **Material 3** — tema chiaro/scuro personalizzabile
- **Google Gemini** — lettura AI degli scontrini (cloud, gratuita); **Google
  ML Kit** — OCR offline di fallback
- **fl_chart** — grafici della dashboard
- **Turso** — sincronizzazione cloud multi-dispositivo via API HTTP (Hrana),
  non tramite client nativo libSQL (evita la toolchain Rust in build)
- **googleapis** / **googleapis_auth** — bridge temporaneo (Impostazioni >
  Admin) verso il foglio Google usato finora per le spese, disattivabile;
  da rimuovere quando l'app sarà completa e testata al 100%

## Requisiti

- **Flutter SDK** (canale stable) e Dart
- Per la build **Android**: Android SDK (via Android Studio o command-line tools)
- Per la build **Windows desktop**: **Visual Studio 2022** con il workload
  *"Sviluppo di applicazioni desktop con C++"* (non serve Android Studio)
- **Git**

## Come avviare il progetto

```bash
# 1. Scarica le dipendenze
flutter pub get

# 2. Genera il codice (tabelle Drift + provider Riverpod)
dart run build_runner build --delete-conflicting-outputs

# 3a. Avvia su Android (dispositivo/emulatore collegato)
flutter run

# 3b. Oppure avvia come app desktop Windows
flutter config --enable-windows-desktop
flutter run -d windows
```

Verifica che l'ambiente sia a posto con:

```bash
flutter doctor
```

## Stato del progetto

Sviluppo per milestone incrementali, ognuna progettata e documentata prima di
scrivere codice (v. `progettazione_finance_app.md`, sezione 6, per il
dettaglio di ciascuna e per il processo da seguire per le prossime). Tutte le
milestone M0-M21 sono completate (M22-M24 proposte, in attesa di sviluppo).
Integrazione continua attiva
(`.github/workflows/ci.yml`): `flutter analyze` + `flutter test` a ogni push/PR.

| Milestone | Contenuto | Stato |
|-----------|-----------|-------|
| **M0** | Setup: Clean Architecture, tema Material 3, bottom navigation, schema DB Drift completo, seed dati di default | ✅ Completata |
| **M1** | `TransactionRepositoryImpl`, schermata "Nuova Operazione" con tastierino, Home reale | ✅ Completata |
| **M2** | Categorie personalizzabili, modulo Budget | ✅ Completata |
| **M3** | Scansione scontrini: fotocamera + OCR ML Kit, poi sostituito da Google Gemini (AI cloud) con fallback OCR, + regole di classificazione | ✅ Completata |
| **M4** | Grafici dashboard (fl_chart) | ✅ Completata |
| **M5** | Movimenti ricorrenti | ✅ Completata |
| **M6** | Ricerca, import/export CSV | ✅ Completata |
| **M7** | Sync multi-dispositivo su Turso + build desktop/Android | ✅ Completata |
| **M8** | Rifinitura: fix bug di sync, audit best-practice, dedupe tassonomia, empty states + animazioni, tema unificato sull'icona, rename a "Tally", CI (`flutter analyze`/`flutter test`), test estesi (motore di sync + DAO) | ✅ Completata |
| **M9** | Admin (import CSV, bridge Google Sheets temporaneo, eliminazione definitiva/pulizia transazioni con conferma remota), fix reattività riordino categorie | ✅ Completata |
| **M10** | Icona app e splash screen Android/Windows con il logo Tally | ✅ Completata |
| **M11** | Robustezza doppioni transazioni pre-sync (fix crash + pulizia backlog) e avviso doppioni in "Nuova Operazione" | ✅ Completata |
| **M12** | Build Android release funzionante (fix ProGuard/R8) | ✅ Completata |
| **M13** | Blocco nomi categoria duplicati + strumento "Unisci con..." | ✅ Completata |
| **M14** | Ricorrenze a numero di occorrenze finito (schema v7) + fix schema remoto Turso | ✅ Completata |
| **M15** | Import estratto conto bancario (Impostazioni, primo parser BancoPosta) | ✅ Completata |
| **M16** | Ricerca per sottocategoria, fix tooltip dashboard, fix quota storage Artifacts CI | ✅ Completata |
| **M17** | Migrazione schema locale idempotente (fix avvio bloccato su migrazione interrotta) | ✅ Completata |
| **M18** | Fix sicurezza: la API key Gemini non può più comparire in un messaggio d'errore mostrato all'utente | ✅ Completata |
| **M19** | Gestione errori su cancellazione transazione (Home/Storico): un fallimento ora mostra sempre una snackbar | ✅ Completata |
| **M20** | Verifica tag `+eol` su `sqlite3_flutter_libs`: l'upgrade richiede prima Drift ≥2.32, spostato dentro M24 | ✅ Completata |
| **M21** | Timeout (30s) su tutte le chiamate di rete del bridge Google Sheets, "Test connessione" non resta più bloccato indefinitamente | ✅ Completata |

## Struttura del database

Schema Drift con le tabelle: `Categories`, `SubCategories`, `Merchants`,
`MerchantRules`, `Transactions`, `Budgets`, `RecurringTransactions`,
`Settings`. Ogni tabella include i campi `updatedAt`, `isDeleted` e `syncId`
per la sincronizzazione su Turso (M7). `Transactions` include inoltre
`refundOfId` (collegamento rimborso→spesa) e `receiptImagePath` (foto dello
scontrino scansionato).

## Note di sviluppo

Il progetto può essere sviluppato indifferentemente su Windows, macOS o Linux.
Su Windows è possibile lavorare **senza Android Studio**, sfruttando la build
desktop: basta Flutter SDK + Visual Studio 2022 con il workload C++.

Documento di design completo: `progettazione_finance_app.md`.
