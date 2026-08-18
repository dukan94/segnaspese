import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../entities/parsed_statement_row.dart';
import '../entities/transaction_entity.dart';
import 'bank_statement_parser.dart';
import 'money_rounding.dart';

/// Parser dell'estratto conto Excel di Poste Italiane (BancoPosta), esportato
/// da "Lista movimenti" nell'home banking.
///
/// Formato osservato (5 ago 2026, v. CLAUDE.md/memoria di progetto): righe
/// iniziali vuote (spazio riservato al logo, numero variabile), poi
/// un'intestazione con le colonne `Data Contabile | Data Valuta | Addebiti
/// (euro) | Accrediti (euro) | Descrizione operazioni`, poi le righe di
/// movimento senza un footer da scartare. Le date sono seriali Excel con
/// stile numerico data (`numFmtId` 14): il pacchetto `excel` le decodifica
/// già come [DateCellValue]; il fallback su seriale grezzo copre file dove
/// la cella non ha uno stile data esplicito.
///
/// **Data Valuta, non Data Contabile** (bug reale, segnalato da Mario 16 ago
/// 2026): la colonna usata per popolare [ParsedStatementRow.date] è la
/// seconda (Data Valuta), non la prima (Data Contabile) — quest'ultima serve
/// solo ad ancorare la ricerca della riga di intestazione (v. sotto), non è
/// la data della transazione. La data contabile è quando la banca registra
/// il movimento (può slittare di giorni per weekend/elaborazione batch); la
/// data valuta è quella con cui il movimento incide sul saldo, molto più
/// vicina al giorno reale della spesa per i pagamenti POS.
class BancoPostaStatementParser implements BankStatementParser {
  const BancoPostaStatementParser();

  static const _dataContabile = 'data contabile';

  @override
  String get bankName => 'Poste Italiane (BancoPosta)';

  @override
  List<ParsedStatementRow> parse(Uint8List bytes) {
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (e) {
      throw FormatException('File Excel non leggibile: $e');
    }
    if (workbook.tables.isEmpty) {
      throw const FormatException('Il file Excel non contiene fogli.');
    }
    final sheet = workbook.tables.values.first;

    int? headerRow;
    for (var r = 0; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      if (row.isNotEmpty && _text(row[0]).trim().toLowerCase() == _dataContabile) {
        headerRow = r;
        break;
      }
    }
    if (headerRow == null) {
      throw const FormatException(
        'Intestazione non trovata: il file non sembra un estratto conto '
        'BancoPosta (manca la colonna "Data Contabile").',
      );
    }

    final rows = <ParsedStatementRow>[];
    for (var r = headerRow + 1; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      Data? at(int i) => i < row.length ? row[i] : null;

      // Colonna 1 (Data Valuta), non 0 (Data Contabile) — v. commento di
      // classe sopra. Una cella VUOTA (nessun valore) segnala la vera fine
      // dei dati; una cella CON un valore che non decodifica come data è
      // invece una riga malformata (es. cella esportata come testo per una
      // particolarità di locale/formato) — va solo saltata, non deve
      // troncare l'import di tutte le righe successive.
      final dateCell = at(1);
      if (dateCell?.value == null) break; // riga vuota: fine dei dati
      final date = _date(dateCell);
      if (date == null) continue; // riga malformata: si salta, non è la fine del file

      final debitCell = at(2);
      final creditCell = at(3);
      if (debitCell?.value == null && creditCell?.value == null) {
        break; // riga vuota: fine dei dati
      }
      final debit = _amount(debitCell);
      final credit = _amount(creditCell);
      if (debit == null && credit == null) continue; // riga malformata: si salta

      final description = _text(at(4)).replaceAll(RegExp(r'\s+'), ' ').trim();

      rows.add(ParsedStatementRow(
        date: date,
        description: description,
        amount: roundToCents((debit ?? credit)!),
        type: debit != null ? TransactionType.expense : TransactionType.income,
      ));
    }
    return rows;
  }

  String _text(Data? cell) => cell?.value?.toString() ?? '';

  double? _amount(Data? cell) {
    final v = cell?.value;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is DoubleCellValue) return v.value;
    return null;
  }

  DateTime? _date(Data? cell) {
    final v = cell?.value;
    if (v is DateCellValue) return v.asDateTimeLocal();
    if (v is DateTimeCellValue) return v.asDateTimeLocal();
    if (v is IntCellValue) return _serialToDate(v.value.toDouble());
    if (v is DoubleCellValue) return _serialToDate(v.value);
    return null;
  }

  /// Seriale Excel (giorni dal 30/12/1899) → data. Usato solo come fallback
  /// quando la cella non porta uno stile data (v. commento di classe).
  DateTime _serialToDate(double serial) {
    final epoch = DateTime.utc(1899, 12, 30);
    final dt = epoch.add(Duration(milliseconds: (serial * 86400000).round()));
    return DateTime(dt.year, dt.month, dt.day);
  }
}
