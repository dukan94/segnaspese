import 'package:finance_app/data/services/google_sheets_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractSpreadsheetId', () {
    test('estrae l\'id da un URL completo del foglio', () {
      const url =
          'https://docs.google.com/spreadsheets/d/1o-BQYddV-_UFunu9xMob4Ne8OICpI2MLA7LkgZoL_h0/edit?gid=123#gid=123';
      expect(GoogleSheetsService.extractSpreadsheetId(url),
          '1o-BQYddV-_UFunu9xMob4Ne8OICpI2MLA7LkgZoL_h0');
    });

    test('un id già nudo viene restituito invariato', () {
      const id = '1o-BQYddV-_UFunu9xMob4Ne8OICpI2MLA7LkgZoL_h0';
      expect(GoogleSheetsService.extractSpreadsheetId(id), id);
    });
  });

  group('headerMatches', () {
    test('intestazione identica a quella attesa: combacia', () {
      expect(GoogleSheetsService.headerMatches(GoogleSheetsService.expectedHeader), isTrue);
    });

    test('colonne in ordine diverso: non combacia', () {
      final swapped = [...GoogleSheetsService.expectedHeader];
      final tmp = swapped[0];
      swapped[0] = swapped[1];
      swapped[1] = tmp;
      expect(GoogleSheetsService.headerMatches(swapped), isFalse);
    });

    test('colonne extra dopo quelle attese: combacia comunque', () {
      final withExtra = [...GoogleSheetsService.expectedHeader, 'Nota personale'];
      expect(GoogleSheetsService.headerMatches(withExtra), isTrue);
    });

    test('intestazione più corta di quella attesa: non combacia', () {
      final short = GoogleSheetsService.expectedHeader.sublist(0, 3);
      expect(GoogleSheetsService.headerMatches(short), isFalse);
    });

    test('intestazione vuota: non combacia', () {
      expect(GoogleSheetsService.headerMatches(const []), isFalse);
    });
  });
}
