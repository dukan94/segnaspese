import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/bank_statement_parser.dart';
import '../../domain/services/bancoposta_statement_parser.dart';
import '../../domain/services/statement_duplicate_matcher.dart';

/// Un parser per banca. Aggiungere una nuova banca significa implementare
/// [BankStatementParser] e aggiungerla a questa lista — nessun'altra
/// modifica richiesta al resto del flusso di import (v.
/// `presentation/statement_import/statement_import_page.dart`).
final bankStatementParsersProvider = Provider<List<BankStatementParser>>((ref) {
  return const [BancoPostaStatementParser()];
});

final statementDuplicateMatcherProvider =
    Provider<StatementDuplicateMatcher>((ref) {
  return const StatementDuplicateMatcher();
});
