import 'package:finance_app/data/services/google_sheets_row_formatter.dart';
import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TransactionEntity tx({
    required TransactionType type,
    double amount = 20,
    bool isRefund = false,
    bool isExtraordinary = false,
    String? note,
  }) {
    return TransactionEntity(
      date: DateTime(2026, 1, 5),
      amount: amount,
      type: type,
      categoryId: 1,
      subCategoryId: 2,
      note: note,
      isRefund: isRefund,
      isExtraordinary: isExtraordinary,
    );
  }

  test('uscita normale: Tipologia "Spesa", importo positivo', () {
    final row = GoogleSheetsRowFormatter.format(
      transaction: tx(type: TransactionType.expense, amount: 14.44),
      categoryName: 'Spesa',
      subCategoryName: 'Supermercato',
    );

    expect(row, [
      '05/01/2026',
      '14,44 €',
      'Supermercato',
      '',
      '',
      'Spesa',
      'Spesa',
    ]);
  });

  test('entrata: Tipologia "Entrata", importo positivo', () {
    final row = GoogleSheetsRowFormatter.format(
      transaction: tx(type: TransactionType.income, amount: 1691.93),
      categoryName: 'Stipendio',
      subCategoryName: 'Stipendio',
    );

    expect(row[1], '1.691,93 €');
    expect(row[6], 'Entrata');
  });

  test('rimborso: Tipologia "Rimborso", importo negativo (a differenza di signedAmount)', () {
    final row = GoogleSheetsRowFormatter.format(
      transaction: tx(type: TransactionType.expense, amount: 5, isRefund: true),
      categoryName: 'Tempo Libero',
      subCategoryName: 'Abbonamenti',
    );

    expect(row[1], '-5,00 €');
    expect(row[6], 'Rimborso');
  });

  test('spesa straordinaria: colonna "Tipologia Spesa" valorizzata', () {
    final row = GoogleSheetsRowFormatter.format(
      transaction: tx(type: TransactionType.expense, amount: 336.54, isExtraordinary: true),
      categoryName: 'Veicoli & Trasporti',
      subCategoryName: 'Assicurazione',
    );

    expect(row[4], 'Straordinaria');
  });

  test('nota assente: colonna Note vuota, non "null"', () {
    final row = GoogleSheetsRowFormatter.format(
      transaction: tx(type: TransactionType.expense, note: null),
      categoryName: 'Casa',
      subCategoryName: 'Bollette',
    );

    expect(row[3], '');
  });

  test('nota presente: riportata in colonna Note', () {
    final row = GoogleSheetsRowFormatter.format(
      transaction: tx(type: TransactionType.expense, note: 'Netflix'),
      categoryName: 'Tempo Libero',
      subCategoryName: 'Abbonamenti',
    );

    expect(row[3], 'Netflix');
  });
}
