import 'transaction_entity.dart';

/// Riga grezza estratta da un estratto conto bancario (Excel/CSV), prima
/// della revisione da parte dell'utente (categoria, doppioni) in
/// `presentation/statement_import/`.
///
/// L'importo è sempre positivo (come [TransactionEntity.amount]): il segno
/// è già stato risolto in [type] da quale colonna (addebito/accredito) del
/// file lo conteneva.
class ParsedStatementRow {
  const ParsedStatementRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
  });

  final DateTime date;

  /// Causale/descrizione così come appare nel file, con spazi multipli
  /// normalizzati (utile sia per la UI sia per [RuleMatcherService]).
  final String description;

  final double amount;
  final TransactionType type;
}
