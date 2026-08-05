import 'dart:typed_data';

import '../entities/parsed_statement_row.dart';

/// Contratto per i parser di estratto conto bancario, uno per formato/banca
/// (v. `bancoposta_statement_parser.dart` per il primo). Ogni banca esporta
/// un formato diverso: aggiungerne una nuova significa implementare questa
/// interfaccia, senza toccare la UI di `presentation/statement_import/` né
/// il resto del flusso (categorizzazione, dedup, import) che lavora solo su
/// [ParsedStatementRow].
abstract class BankStatementParser {
  /// Nome mostrato nel selettore banca della UI.
  String get bankName;

  /// Estrae i movimenti dal file. Lancia [FormatException] se il file non
  /// sembra nel formato atteso (es. intestazione non trovata) — l'errore
  /// risale alla UI, che lo mostra via snackbar, come da convenzione del
  /// progetto (niente tipi Result/Failure).
  List<ParsedStatementRow> parse(Uint8List bytes);
}
