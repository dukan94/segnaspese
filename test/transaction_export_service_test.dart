import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:finance_app/domain/services/transaction_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const exporter = TransactionCsvExporter();

  test(
      'formato invariato dopo la migrazione da ListToCsvConverter a Csv '
      '(csv 8.x, M24): intestazione, separatore ";", fine riga CRLF',
      () {
    final csv = exporter.buildCsv(
      transactions: [
        TransactionEntity(
          date: DateTime(2026, 8, 1),
          amount: 42.8,
          type: TransactionType.expense,
          categoryId: 1,
          subCategoryId: 2,
          note: 'Spesa',
          isExtraordinary: false,
          isRefund: false,
        ),
      ],
      categoryNameById: {1: 'Casa'},
      subCategoryNameById: {2: 'Spesa'},
    );

    final lines = csv.split('\r\n');
    expect(lines[0],
        'Data;Quanto;Tipo;Categoria;Sub Categoria;Note;Tipologia Spesa;Rimborso');
    expect(lines[1], '01/08/2026;42,80;Uscita;Casa;Spesa;Spesa;Normale;No');
  });

  test('un rimborso ha il segno invertito rispetto a una spesa normale', () {
    final csv = exporter.buildCsv(
      transactions: [
        TransactionEntity(
          date: DateTime(2026, 8, 1),
          amount: 20,
          type: TransactionType.expense,
          categoryId: 1,
          isRefund: true,
        ),
      ],
      categoryNameById: {1: 'Casa'},
      subCategoryNameById: const {},
    );

    expect(csv, contains('-20,00'));
  });
}
