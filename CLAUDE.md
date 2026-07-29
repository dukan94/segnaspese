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
- Test in `test/` (13 file): parser CSV, receipt parser, rule matcher,
  duplicate finder, sync Turso, repair sottocategorie orfane, widget animati,
  DAO ricorrenze/categorie/budget/transazioni (date-math, riordino, upsert,
  filtri ricerca) + 1 smoke widget test.

## Convenzioni

- **Lingua**: UI, commenti e messaggi di commit in **italiano**.
- **Piattaforme generate**: Windows (`windows/`) e Android (`android/`,
  `applicationId` dedicato, permesso INTERNET). Per aggiungerne altre:
  `flutter create --platforms=<piattaforma> .`, poi verificare permessi e
  `minSdk` (≥ 21 per ML Kit/camera). macOS/iOS/Linux non generate.
- **Font importi**: `PublicSans` (OFL) al posto di Aptos Display (proprietario,
  non ridistribuibile). Font variabile, un solo file per tutti i pesi.
- **Lint**: `package:flutter_lints/flutter.yaml` (`analysis_options.yaml`).
- **Segreti** (credenziali Turso, API key Gemini): solo in
  `flutter_secure_storage`, mai committati.

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
