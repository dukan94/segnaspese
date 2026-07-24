import 'package:finance_app/domain/services/receipt_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ReceiptParserService();

  group('ReceiptParserService.extractTotal', () {
    test('preferisce la riga "TOTALE" rispetto ad altri importi', () {
      const text = '''
ESSELUNGA SPA
PANE                 1,20
LATTE                2,49
SUBTOTALE           38,50
TOTALE EURO         42,80
CONTANTI            50,00
RESTO                7,20
''';
      expect(parser.extractTotal(text), 42.80);
    });

    test('gestisce il separatore delle migliaia', () {
      const text = 'TOTALE 1.234,56';
      expect(parser.extractTotal(text), 1234.56);
    });

    test('fallback: importo più alto se manca la parola chiave', () {
      const text = 'ARTICOLO A 10,00\nARTICOLO B 25,90';
      expect(parser.extractTotal(text), 25.90);
    });

    test('gestisce il formato con punto decimale', () {
      const text = 'TOTALE 12.34';
      expect(parser.extractTotal(text), 12.34);
    });

    test('legge un totale intero senza decimali', () {
      const text = 'NEGOZIO X\nPANE 2,00\nTOTALE 10';
      expect(parser.extractTotal(text), 10.0);
    });

    test('legge un totale intero con "EURO"', () {
      const text = 'TABACCHI\nRIVISTA 3,00\nIMPORTO EURO 8';
      expect(parser.extractTotal(text), 8.0);
    });

    test('ignora il conteggio articoli e prende il totale in denaro', () {
      const text = 'COOP\nLATTE 1,50\nTOTALE ARTICOLI 3\nTOTALE 1,50';
      expect(parser.extractTotal(text), 1.50);
    });
  });

  group('ReceiptParserService.extractMerchant', () {
    test('prende la prima riga significativa in alto', () {
      const text = '''
ESSELUNGA SPA
VIA ROMA 1
P.IVA 01234567890
TOTALE 42,80
''';
      expect(parser.extractMerchant(text), 'ESSELUNGA SPA');
    });

    test('salta righe di data e importi iniziali', () {
      const text = '''
12/07/2026 14:32
Q8 STAZIONE SERVIZIO
CARBURANTE 60,00
''';
      expect(parser.extractMerchant(text), 'Q8 STAZIONE SERVIZIO');
    });
  });

  test('parse restituisce sia negozio sia totale', () {
    const text = 'CONAD CITY\nSPESA VARIA\nTOTALE 18,90';
    final result = parser.parse(text);
    expect(result.merchantName, 'CONAD CITY');
    expect(result.total, 18.90);
    expect(result.hasAnyData, isTrue);
  });
}
