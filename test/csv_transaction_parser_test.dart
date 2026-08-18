import 'package:finance_app/domain/services/csv_transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = CsvTransactionParser();

  group('parse (formato utente, tab)', () {
    const csv =
        'Data\tQuanto\tSub Categoria\tNote\tTipologia Spesa\tCategoria\tMese\n'
        '05/07/2026\t23,93 €\t🍴 Acquisti Extra\tZanzariere\t\t🛍️ Acquisti\tLUGLIO\n'
        '10/07/2026\t-1.742,24 €\t💳 Stipendio\t\t\t💳 Stipendio\tLUGLIO\n'
        '09/07/2026\t-49,37 €\t🛒 Spesa\tRestituzione Nico\tStraordinaria\t🏢 Casa\tLUGLIO';

    test('nessuna colonna mancante', () {
      expect(parser.parse(csv).hasHeaderError, isFalse);
    });

    test('importo positivo, data, note e nome sottocategoria', () {
      final row = parser.parse(csv).rows[0];
      expect(row.signedAmount, 23.93);
      expect(row.date, DateTime(2026, 7, 5));
      expect(row.note, 'Zanzariere');
      expect(row.subCategoryName, '🍴 Acquisti Extra');
      expect(row.isExtraordinary, isFalse);
    });

    test('mantiene il segno negativo (migliaia gestite)', () {
      expect(parser.parse(csv).rows[1].signedAmount, -1742.24);
      expect(parser.parse(csv).rows[2].signedAmount, -49.37);
    });

    test('flag straordinaria da "Tipologia Spesa"', () {
      expect(parser.parse(csv).rows[2].isExtraordinary, isTrue);
    });
  });

  test('separatore ; e importi positivi', () {
    const csv = 'Data;Quanto;Sub Categoria\n'
        '11/07/2026;41,00 €;Ristorante / Uscita';
    final row = parser.parse(csv).rows.single;
    expect(row.signedAmount, 41.00);
    expect(row.subCategoryName, 'Ristorante / Uscita');
  });

  test(
      'una data con un giorno che non esiste nel mese (31/04) è segnalata '
      'come riga non valida, non normalizzata silenziosamente all\'1 maggio',
      () {
    const csv = 'Data;Quanto;Sub Categoria\n'
        '31/04/2026;10,00 €;Ristorante / Uscita';
    final row = parser.parse(csv).rows.single;
    expect(row.error, isNotNull);
    expect(row.date, isNull);
  });

  test('intestazione senza colonne obbligatorie → errore', () {
    const csv = 'Colonna1;Colonna2\na;b';
    final result = parser.parse(csv);
    expect(result.hasHeaderError, isTrue);
    expect(result.missingColumns, contains('Data'));
  });

  test('normalizeName rimuove emoji e uniforma', () {
    expect(CsvTransactionParser.normalizeName('🛒 Supermercato'), 'supermercato');
    expect(CsvTransactionParser.normalizeName('  Ristorante /  Uscita '),
        'ristorante / uscita');
  });
}
