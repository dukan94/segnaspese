# SegnaSpese — Monitoraggio Spese con Scansione Scontrini

App multipiattaforma (Flutter) per **tenere sotto controllo le spese personali**:
scansiona lo scontrino, riconosce automaticamente le voci di spesa, le
categorizza e le salva in un database locale, con dashboard, budget e
movimenti ricorrenti. Nata come app Android, gira anche come **applicazione
desktop Windows** grazie a Flutter.

## Funzionalità principali

- **Scansione scontrini con OCR** — riconoscimento delle spese dallo scontrino
  (Google ML Kit) e regole di classificazione automatica per assegnare la
  categoria giusta.
- **Categorizzazione** — categorie e sottocategorie personalizzabili, con
  regole per merchant.
- **Inserimento manuale** — schermata "Nuova Operazione" con tastierino rapido
  per aggiungere spese a mano.
- **Dashboard** — grafici e riepiloghi per monitorare l'andamento delle spese.
- **Budget** — definizione e controllo dei budget per categoria.
- **Movimenti ricorrenti** — gestione di spese/entrate che si ripetono.
- **Ricerca e import/export** — ricerca movimenti ed esportazione Excel/CSV.
- **Sync multi-dispositivo** — sincronizzazione tra dispositivi (Turso), con
  build desktop dedicata.

## Stack tecnologico

- **Flutter / Dart** — UI multipiattaforma (Android, Windows desktop, ecc.)
- **Clean Architecture** — separazione in `core` / `domain` / `data` / `presentation`
- **Drift** — database locale relazionale con codice generato
- **Riverpod** — state management e dependency injection
- **Material 3** — tema chiaro/scuro
- **Google ML Kit** — OCR degli scontrini
- **fl_chart** — grafici della dashboard
- **Turso** — sincronizzazione cloud multi-dispositivo

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

Sviluppo per milestone incrementali.

| Milestone | Contenuto | Stato |
|-----------|-----------|-------|
| **M0** | Setup: Clean Architecture, tema Material 3, bottom navigation, schema DB Drift completo, seed dati di default | ✅ Completata |
| **M1** | `TransactionRepositoryImpl`, schermata "Nuova Operazione" con tastierino, Home reale | 🔜 In corso |
| **M2** | Categorie personalizzabili, modulo Budget | ⏳ |
| **M3** | OCR scontrini (Google ML Kit) + regole di classificazione | ⏳ |
| **M4** | Grafici dashboard (fl_chart) | ⏳ |
| **M5** | Movimenti ricorrenti | ⏳ |
| **M6** | Ricerca, import/export Excel/CSV | ⏳ |
| **M7** | Sync multi-dispositivo su Turso + build desktop | ⏳ |
| **M8** | Rifinitura, test, animazioni | ⏳ |

## Struttura del database (M0)

Schema Drift con le tabelle: `Categories`, `SubCategories`, `Merchants`,
`MerchantRules`, `Transactions`, `Budgets`, `RecurringTransactions`,
`Settings`. Ogni tabella include i campi `updatedAt` e `isDeleted` per
supportare la futura sincronizzazione su Turso (M7).

## Note di sviluppo

Il progetto può essere sviluppato indifferentemente su Windows, macOS o Linux.
Su Windows è possibile lavorare **senza Android Studio**, sfruttando la build
desktop: basta Flutter SDK + Visual Studio 2022 con il workload C++.

Documento di design completo: `progettazione_finance_app.md`.
