/// Arrotonda a 2 decimali (i centesimi di una valuta): alcuni importi
/// arrivano da calcoli in virgola mobile con un errore di rappresentazione
/// binaria (es. `40.799999999999997` invece di `40.8`), sia da un file
/// esterno (estratto conto) sia da un'operazione aritmetica interna (es. una
/// divisione per un rimborso con divisore).
///
/// Unico punto di questa formula in tutto il progetto: prima era duplicata
/// identica in 3 punti (`bancoposta_statement_parser.dart`,
/// `build_split_refund.dart`, e inline in `split_refund_sheet.dart`), con il
/// rischio che una correzione futura ne aggiornasse solo una copia lasciando
/// le altre silenziosamente indietro.
double roundToCents(double value) => (value * 100).round() / 100;
