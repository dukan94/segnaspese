/// Riga grezza estratta dal CSV, prima della risoluzione della sottocategoria
/// verso gli id del database.
///
/// Il parser NON decide entrata/uscita: mantiene l'importo col segno. Il tipo
/// viene stabilito a valle dalla categoria abbinata alla sottocategoria, e un
/// importo negativo su una categoria di spesa è interpretato come rimborso.
class CsvTransactionRow {
  const CsvTransactionRow({
    required this.lineNumber,
    this.date,
    this.signedAmount,
    this.subCategoryName = '',
    this.note,
    this.isExtraordinary = false,
    this.error,
  });

  final int lineNumber;
  final DateTime? date;

  /// Importo con segno così com'è nel file (negativo = rimborso/entrata).
  final double? signedAmount;

  /// Nome sottocategoria così com'è nel file (può contenere emoji).
  final String subCategoryName;
  final String? note;
  final bool isExtraordinary;

  /// Messaggio d'errore se la riga non è interpretabile.
  final String? error;

  bool get isValid => error == null;
}

/// Esito del parsing dell'intero file.
class CsvParseResult {
  const CsvParseResult({required this.rows, required this.missingColumns});

  final List<CsvTransactionRow> rows;

  /// Colonne obbligatorie non trovate nell'intestazione.
  final List<String> missingColumns;

  bool get hasHeaderError => missingColumns.isNotEmpty;
}

/// Parser puro del CSV delle operazioni esportato dall'utente (da Excel).
///
/// Tollerante: rileva il separatore (;, tab o ,), riconosce intestazioni con
/// nomi alternativi, importi in formato italiano (con € e separatore migliaia),
/// date gg/mm/aaaa e il tipo dalla colonna Entrata/Uscita (con fallback dal
/// segno dell'importo, se la colonna manca).
class CsvTransactionParser {
  const CsvTransactionParser();

  static const _dateAliases = ['data', 'date'];
  static const _amountAliases = ['quanto', 'importo', 'amount'];
  static const _subAliases = ['sub categoria', 'sottocategoria', 'subcategoria', 'sub-categoria'];
  static const _noteAliases = ['note', 'nota', 'descrizione'];
  static const _extraAliases = [
    'tipologia spesa',
    'tipologia',
    'straordinaria',
    'straordinaria?',
  ];

  CsvParseResult parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return const CsvParseResult(rows: [], missingColumns: ['(file vuoto)']);
    }

    final delimiter = _detectDelimiter(lines.first);
    final header = _splitLine(lines.first, delimiter).map(_normHeader).toList();

    int? indexOf(List<String> aliases) {
      for (var i = 0; i < header.length; i++) {
        if (aliases.contains(header[i])) return i;
      }
      return null;
    }

    final iDate = indexOf(_dateAliases);
    final iAmount = indexOf(_amountAliases);
    final iSub = indexOf(_subAliases);
    final iNote = indexOf(_noteAliases);
    final iExtra = indexOf(_extraAliases);

    final missing = <String>[];
    if (iDate == null) missing.add('Data');
    if (iAmount == null) missing.add('Quanto/Importo');
    if (iSub == null) missing.add('Sub Categoria');
    if (missing.isNotEmpty) {
      return CsvParseResult(rows: const [], missingColumns: missing);
    }

    final rows = <CsvTransactionRow>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitLine(lines[i], delimiter);
      String cell(int? idx) =>
          (idx != null && idx < cells.length) ? cells[idx].trim() : '';

      final lineNo = i + 1;
      final date = _parseDate(cell(iDate));
      final signed = _parseAmount(cell(iAmount));
      final sub = cell(iSub);

      if (date == null || signed == null || sub.isEmpty) {
        rows.add(CsvTransactionRow(
          lineNumber: lineNo,
          subCategoryName: sub,
          error: 'Riga non valida (data/importo/sottocategoria mancanti)',
        ));
        continue;
      }

      final extraStr = _normHeader(cell(iExtra));
      final isExtra = extraStr.contains('straordinar');

      rows.add(CsvTransactionRow(
        lineNumber: lineNo,
        date: date,
        signedAmount: signed,
        subCategoryName: sub,
        note: iNote != null && cell(iNote).isNotEmpty ? cell(iNote) : null,
        isExtraordinary: isExtra,
      ));
    }

    return CsvParseResult(rows: rows, missingColumns: const []);
  }

  String _detectDelimiter(String headerLine) {
    final counts = {
      ';': ';'.allMatches(headerLine).length,
      '\t': '\t'.allMatches(headerLine).length,
      ',': ','.allMatches(headerLine).length,
    };
    var best = ';';
    var bestCount = -1;
    counts.forEach((d, c) {
      if (c > bestCount) {
        best = d;
        bestCount = c;
      }
    });
    return best;
  }

  /// Split di una riga con gestione minimale delle virgolette.
  List<String> _splitLine(String line, String delimiter) {
    final result = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == delimiter && !inQuotes) {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString());
    return result;
  }

  String _normHeader(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  DateTime? _parseDate(String s) {
    final parts = s.split(RegExp(r'[/\-.]'));
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    var y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final result = DateTime(y, m, d);
    // Il controllo sopra valida solo i range indipendenti (1-12, 1-31), non
    // che il giorno esista davvero in quel mese: DateTime normalizza in
    // silenzio un giorno fuori range (es. 31/04 -> 1 maggio) invece di
    // lanciare un'eccezione. Se i componenti del risultato non coincidono
    // con quelli richiesti, la data non era valida.
    if (result.year != y || result.month != m || result.day != d) return null;
    return result;
  }

  double? _parseAmount(String s) {
    // Tiene solo cifre, separatori e segno; scarta €, spazi, ecc.
    var t = s.replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (t.isEmpty) return null;
    final lastComma = t.lastIndexOf(',');
    final lastDot = t.lastIndexOf('.');

    if (lastComma >= 0 && lastDot >= 0) {
      // Entrambi i separatori presenti: quello più a destra è il decimale,
      // l'altro è il separatore delle migliaia (es. "1.234,56" o "1,234.56").
      final decimalSep = lastComma > lastDot ? ',' : '.';
      final thousandsSep = decimalSep == ',' ? '.' : ',';
      t = t.replaceAll(thousandsSep, '').replaceAll(decimalSep, '.');
    } else if (lastComma >= 0) {
      // Solo virgole: in convenzione italiana la virgola è il decimale; più
      // virgole = separatori delle migliaia (es. "1,234,567").
      t = ','.allMatches(t).length > 1
          ? t.replaceAll(',', '')
          : t.replaceAll(',', '.');
    } else if (lastDot >= 0) {
      // Solo punti: è un decimale solo se c'è un unico punto seguito da 1-2
      // cifre (es. "12.50"). Altrimenti è separatore delle migliaia e va
      // rimosso — così "1.500" resta 1500, non 1,5 (bug precedente).
      final decimals = t.length - lastDot - 1;
      final singleDot = '.'.allMatches(t).length == 1;
      if (!(singleDot && decimals >= 1 && decimals <= 2)) {
        t = t.replaceAll('.', '');
      }
    }
    return double.tryParse(t);
  }

  /// Normalizza un nome (categoria/sottocategoria) per il confronto: rimuove
  /// emoji e simboli, riduce spazi, minuscolo. Usata sia sul CSV sia sui nomi
  /// del database.
  static String normalizeName(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[a-zà-ÿ0-9 /]').hasMatch(ch)) buf.write(ch);
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
