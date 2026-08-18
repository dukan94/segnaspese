import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:finance_app/domain/services/bancoposta_statement_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Costruisce un file xlsx sintetico che ricalca la struttura reale
/// dell'export "Lista movimenti" di BancoPosta (righe vuote iniziali per il
/// logo, poi intestazione, poi movimenti) — mai il file vero, che contiene
/// dati finanziari reali (v. CLAUDE.md).
Uint8List _buildWorkbook({
  int blankRowsBeforeHeader = 11,
  required List<List<CellValue?>> dataRows,
  List<CellValue?>? header,
}) {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet()!;
  final sheet = excel[sheetName];

  for (var i = 0; i < blankRowsBeforeHeader; i++) {
    sheet.appendRow(const [null, null, null, null, null]);
  }
  sheet.appendRow(header ??
      [
        TextCellValue('Data Contabile'),
        TextCellValue('Data Valuta'),
        TextCellValue('Addebiti (euro)'),
        TextCellValue('Accrediti (euro)'),
        TextCellValue('Descrizione operazioni'),
      ]);
  for (final row in dataRows) {
    sheet.appendRow(row);
  }

  return Uint8List.fromList(excel.encode()!);
}

void main() {
  const parser = BancoPostaStatementParser();

  test('nome banca', () {
    expect(parser.bankName, contains('BancoPosta'));
  });

  test(
      'riga PAGAMENTO POS → uscita, importo e descrizione corretti, data '
      'presa dalla colonna Data Valuta (non Data Contabile, bug reale 16 ago 2026)',
      () {
    final bytes = _buildWorkbook(dataRows: [
      [
        // Data Contabile e Data Valuta diverse apposta: se il parser
        // leggesse ancora la colonna sbagliata (Data Contabile), questo
        // test lo scoprirebbe subito.
        const DateCellValue(year: 2026, month: 8, day: 5),
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DoubleCellValue(8.0),
        null,
        TextCellValue(
            'PAGAMENTO POS SAPORI DI PUGLIA DI PO 03/08/2026 13.11 DESIO         Op.650492 carta ****3082'),
      ],
    ]);

    final rows = parser.parse(bytes);
    expect(rows, hasLength(1));
    expect(rows.single.date, DateTime(2026, 8, 3)); // Data Valuta, non Contabile
    expect(rows.single.amount, 8.0);
    expect(rows.single.type, TransactionType.expense);
    expect(rows.single.description, contains('SAPORI DI PUGLIA'));
    // Spazi multipli normalizzati (padding fisso del formato BancoPosta).
    expect(rows.single.description, isNot(contains('  ')));
  });

  test('riga BONIFICO in accredito → entrata', () {
    final bytes = _buildWorkbook(dataRows: [
      [
        const DateCellValue(year: 2026, month: 8, day: 5),
        const DateCellValue(year: 2026, month: 8, day: 5),
        null,
        const DoubleCellValue(50.0),
        TextCellValue('BONIFICO SEPA ISTANTANEO TRN ... DA COSTA ALFONSO PER Regalo'),
      ],
    ]);

    final row = parser.parse(bytes).single;
    expect(row.type, TransactionType.income);
    expect(row.amount, 50.0);
  });

  test('arrotonda a 2 decimali un importo con errore di rappresentazione binaria', () {
    final bytes = _buildWorkbook(dataRows: [
      [
        const DateCellValue(year: 2026, month: 5, day: 1),
        const DateCellValue(year: 2026, month: 5, day: 1),
        // Stesso valore osservato nel file reale: 40.799999999999997.
        const DoubleCellValue(40.799999999999997),
        null,
        TextCellValue('PAGAMENTO POS BRAVI FARMACIA SRL'),
      ],
    ]);

    expect(parser.parse(bytes).single.amount, 40.8);
  });

  test('si ferma alla prima riga vuota dopo i dati (niente righe fantasma)', () {
    final bytes = _buildWorkbook(dataRows: [
      [
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DoubleCellValue(1.26),
        null,
        TextCellValue('PAGAMENTO POS MD LISSONE'),
      ],
      [null, null, null, null, null],
      [
        const DateCellValue(year: 2026, month: 8, day: 4),
        const DateCellValue(year: 2026, month: 8, day: 4),
        const DoubleCellValue(2.0),
        null,
        TextCellValue('Riga dopo il vuoto, non deve comparire'),
      ],
    ]);

    expect(parser.parse(bytes), hasLength(1));
  });

  test(
      'una riga malformata a metà file (data non decodificabile, non vuota) '
      'viene saltata invece di troncare le righe successive', () {
    final bytes = _buildWorkbook(dataRows: [
      [
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DoubleCellValue(1.26),
        null,
        TextCellValue('PAGAMENTO POS MD LISSONE'),
      ],
      [
        // Cella Data Valuta con un valore non decodificabile come data
        // (testo invece di data/seriale) — non una cella vuota: non deve
        // essere confusa con la fine dei dati.
        const DateCellValue(year: 2026, month: 8, day: 4),
        TextCellValue('n/d'),
        const DoubleCellValue(5.0),
        null,
        TextCellValue('Riga malformata'),
      ],
      [
        const DateCellValue(year: 2026, month: 8, day: 5),
        const DateCellValue(year: 2026, month: 8, day: 5),
        const DoubleCellValue(2.0),
        null,
        TextCellValue('Riga dopo quella malformata, deve comunque comparire'),
      ],
    ]);

    final rows = parser.parse(bytes);
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.description),
        containsAll(['PAGAMENTO POS MD LISSONE', contains('deve comunque comparire')]));
  });

  test(
      'una riga malformata a metà file (addebito/accredito non decodificabile, '
      'non vuoto) viene saltata invece di troncare le righe successive', () {
    final bytes = _buildWorkbook(dataRows: [
      [
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DateCellValue(year: 2026, month: 8, day: 3),
        const DoubleCellValue(1.26),
        null,
        TextCellValue('PAGAMENTO POS MD LISSONE'),
      ],
      [
        const DateCellValue(year: 2026, month: 8, day: 4),
        const DateCellValue(year: 2026, month: 8, day: 4),
        // Addebito non numerico (non vuoto): riga malformata, non fine dati.
        TextCellValue('n/d'),
        null,
        TextCellValue('Riga malformata'),
      ],
      [
        const DateCellValue(year: 2026, month: 8, day: 5),
        const DateCellValue(year: 2026, month: 8, day: 5),
        const DoubleCellValue(2.0),
        null,
        TextCellValue('Riga dopo quella malformata, deve comunque comparire'),
      ],
    ]);

    final rows = parser.parse(bytes);
    expect(rows, hasLength(2));
  });

  test('numero variabile di righe vuote prima dell\'intestazione', () {
    final bytes = _buildWorkbook(
      blankRowsBeforeHeader: 3,
      dataRows: [
        [
          const DateCellValue(year: 2026, month: 8, day: 3),
          const DateCellValue(year: 2026, month: 8, day: 3),
          const DoubleCellValue(2.9),
          null,
          TextCellValue('IMPOSTA DI BOLLO'),
        ],
      ],
    );

    expect(parser.parse(bytes), hasLength(1));
  });

  test('intestazione non trovata → FormatException', () {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet()!;
    excel[sheetName].appendRow([TextCellValue('Colonna a caso')]);
    final bytes = Uint8List.fromList(excel.encode()!);

    expect(() => parser.parse(bytes), throwsFormatException);
  });
}
