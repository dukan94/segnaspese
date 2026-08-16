import 'package:flutter/material.dart';

/// Soglia sopra la quale la finestra è considerata "larga" (desktop-like):
/// oltre questo punto la navigazione passa da bottom bar a [NavigationRail]
/// (v. `root_scaffold.dart`) e le pagine adattate possono riorganizzare il
/// contenuto in righe/colonne invece di impilarlo. Coerente con le linee
/// guida Material 3 per il passaggio bottom navigation → rail (~840-905dp).
///
/// Refactor desktop richiesto da Mario, 16 ago 2026 (v. progettazione,
/// milestone M26).
const double kWideWindowBreakpoint = 900;

bool isWideWindow(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideWindowBreakpoint;
