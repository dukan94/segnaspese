# Finance App — Milestone M0

Setup iniziale del progetto secondo la progettazione approvata: Clean
Architecture, tema Material 3, routing con bottom navigation, schema
database Drift completo (con i campi di sync per Turso) e seed dei dati
di default.

## Come avviare il progetto

```bash
flutter pub get

# Genera il codice Drift (tabelle) e Riverpod (provider)
dart run build_runner build --delete-conflicting-outputs

# Avvia su un dispositivo/emulatore collegato
flutter run

# Oppure su desktop (richiede piattaforma abilitata)
flutter config --enable-windows-desktop   # o macos-desktop / linux-desktop
flutter run -d windows                    # o macos / linux
```

## Cosa contiene questa milestone (M0)

- Struttura cartelle Clean Architecture (`core` / `domain` / `data` / `presentation`)
- Schema database Drift completo: `Categories`, `SubCategories`, `Merchants`,
  `MerchantRules`, `Transactions`, `Budgets`, `RecurringTransactions`,
  `Settings` — con i campi `updatedAt` / `isDeleted` necessari per la
  futura sync su Turso (Milestone M7)
- Tema Material 3 chiaro/scuro
- Routing con bottom navigation a 5 voci (Home, Dashboard, Ricorrenze,
  Budget, Impostazioni) — pagine ancora placeholder
- Seed automatico delle categorie e delle regole di classificazione
  scontrini di default al primo avvio
- Entità di dominio e interfaccia `TransactionRepository` (implementazione
  concreta in arrivo con M1)
- Contratto `SyncService` (stub, implementazione completa in M7)

## Prossimi passi

- **M1**: implementazione completa di `TransactionRepositoryImpl`,
  schermata "Nuova Operazione" con tastierino rapido, Home reale
- **M2**: gestione categorie personalizzabili, modulo Budget
- **M3**: OCR scontrini (Google ML Kit) + regole di classificazione
- **M4**: grafici dashboard (fl_chart)
- **M5**: movimenti ricorrenti
- **M6**: ricerca, import/export Excel/CSV
- **M7**: sync multi-dispositivo su Turso + build desktop
- **M8**: rifinitura, test, animazioni

Vedi `progettazione_finance_app.md` per il documento di design completo.
