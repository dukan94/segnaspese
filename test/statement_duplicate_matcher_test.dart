import 'package:finance_app/domain/entities/parsed_statement_row.dart';
import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:finance_app/domain/services/statement_duplicate_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matcher = StatementDuplicateMatcher(toleranceDays: 3);

  ParsedStatementRow row({
    required DateTime date,
    double amount = 20,
    TransactionType type = TransactionType.expense,
    String description = 'PAGAMENTO POS TEST',
  }) =>
      ParsedStatementRow(
          date: date, description: description, amount: amount, type: type);

  TransactionEntity tx({
    required DateTime date,
    double amount = 20,
    TransactionType type = TransactionType.expense,
    int categoryId = 1,
  }) =>
      TransactionEntity(
          date: date, amount: amount, type: type, categoryId: categoryId);

  test('stesso importo/tipo, stessa data → doppione', () {
    final existing = [tx(date: DateTime(2026, 8, 3))];
    expect(
      matcher.isPossibleDuplicate(row(date: DateTime(2026, 8, 3)), existing),
      isTrue,
    );
  });

  test('stesso importo/tipo, data entro la tolleranza → doppione', () {
    final existing = [tx(date: DateTime(2026, 8, 3))];
    expect(
      matcher.isPossibleDuplicate(row(date: DateTime(2026, 8, 6)), existing),
      isTrue,
    );
  });

  test('data oltre la tolleranza → non doppione', () {
    final existing = [tx(date: DateTime(2026, 8, 3))];
    expect(
      matcher.isPossibleDuplicate(row(date: DateTime(2026, 8, 7)), existing),
      isFalse,
    );
  });

  test('importo diverso → non doppione', () {
    final existing = [tx(date: DateTime(2026, 8, 3), amount: 20)];
    expect(
      matcher.isPossibleDuplicate(
          row(date: DateTime(2026, 8, 3), amount: 20.01), existing),
      isFalse,
    );
  });

  test('tipo diverso (entrata vs uscita) → non doppione', () {
    final existing = [tx(date: DateTime(2026, 8, 3), type: TransactionType.income)];
    expect(
      matcher.isPossibleDuplicate(
          row(date: DateTime(2026, 8, 3), type: TransactionType.expense),
          existing),
      isFalse,
    );
  });

  test('nessuna transazione esistente → non doppione', () {
    expect(matcher.isPossibleDuplicate(row(date: DateTime(2026, 8, 3)), []),
        isFalse);
  });

  test('importo con errore di rappresentazione binaria → considerato uguale', () {
    final existing = [tx(date: DateTime(2026, 8, 3), amount: 40.8)];
    expect(
      matcher.isPossibleDuplicate(
          row(date: DateTime(2026, 8, 3), amount: 40.799999999999997),
          existing),
      isTrue,
    );
  });
}
