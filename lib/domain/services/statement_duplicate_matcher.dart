import '../entities/parsed_statement_row.dart';
import '../entities/transaction_entity.dart';

/// Individua transazioni già presenti in locale che potrebbero corrispondere
/// a una riga di un estratto conto appena importato — per proporle come
/// "possibile doppione" in revisione (v. presentation/statement_import/),
/// non per un blocco automatico: la scelta finale resta all'utente.
///
/// Tolleranza voluta: a differenza di `transaction_duplicate_finder.dart`
/// (match esatto su tutti i campi, usato dalla sync per riconoscere lo
/// stesso movimento arrivato da un altro device), qui una transazione
/// inserita a mano ha quasi certamente nota/categoria diverse da quelle
/// dedotte dall'estratto conto — l'unico segnale affidabile è importo
/// identico e data vicina. `bancoposta_statement_parser.dart` usa la Data
/// Valuta (non la Data Contabile, più lontana dal giorno reale — bug
/// corretto il 16 ago 2026), quindi generalmente già vicina al giorno reale
/// della spesa; la tolleranza resta comunque utile come margine di
/// sicurezza (es. valuta calcolata su un giorno non lavorativo, o la spesa
/// inserita a mano con un giorno di scarto).
class StatementDuplicateMatcher {
  const StatementDuplicateMatcher({this.toleranceDays = 3});

  final int toleranceDays;

  bool isPossibleDuplicate(
    ParsedStatementRow row,
    List<TransactionEntity> existing,
  ) {
    return existing.any((t) =>
        t.type == row.type &&
        _sameAmount(t.amount, row.amount) &&
        _withinTolerance(t.date, row.date));
  }

  /// Confronto sui centesimi, non sul double grezzo: gli importi letti da
  /// Excel possono avere errori di rappresentazione binaria (v.
  /// `bancoposta_statement_parser.dart`), quindi `==` diretto su double
  /// romperebbe il match anche per lo stesso identico importo.
  bool _sameAmount(double a, double b) => (a * 100).round() == (b * 100).round();

  bool _withinTolerance(DateTime a, DateTime b) =>
      a.difference(b).inDays.abs() <= toleranceDays;
}
