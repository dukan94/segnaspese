import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../entities/transaction_entity.dart';

/// Genera il CSV delle operazioni, con colonne compatibili con l'import
/// dell'app (Data, Quanto, Sub Categoria, Note, Tipologia Spesa) più colonne
/// informative (Tipo, Categoria, Rimborso) che l'import ignora.
///
/// Convenzione del segno, identica a quella letta dall'import: il tipo
/// (entrata/uscita) è determinato dalla sottocategoria, mentre il SEGNO
/// dell'importo codifica il rimborso — un'uscita normale è positiva, un
/// rimborso è negativo. Così un file esportato può essere ri-importato senza
/// perdite.
class TransactionCsvExporter {
  const TransactionCsvExporter();

  static final DateFormat _date = DateFormat('dd/MM/yyyy');

  static const List<String> header = [
    'Data',
    'Quanto',
    'Tipo',
    'Categoria',
    'Sub Categoria',
    'Note',
    'Tipologia Spesa',
    'Rimborso',
  ];

  String buildCsv({
    required List<TransactionEntity> transactions,
    required Map<int, String> categoryNameById,
    required Map<int, String> subCategoryNameById,
  }) {
    final sorted = [...transactions]..sort((a, b) => a.date.compareTo(b.date));

    final rows = <List<dynamic>>[header];
    for (final t in sorted) {
      // Segno = convenzione import: uscita normale positiva, rimborso negativo;
      // le entrate sono sempre positive (non sono mai rimborsi).
      final signed = t.isRefund ? -t.amount : t.amount;
      rows.add([
        _date.format(t.date),
        _amount(signed),
        t.type == TransactionType.income ? 'Entrata' : 'Uscita',
        categoryNameById[t.categoryId] ?? '',
        t.subCategoryId != null
            ? (subCategoryNameById[t.subCategoryId!] ?? '')
            : '',
        t.note ?? '',
        t.isExtraordinary ? 'Straordinaria' : 'Normale',
        t.isRefund ? 'Sì' : 'No',
      ]);
    }

    // Separatore ';' (default dei CSV italiani in Excel) e fine riga Windows.
    return const ListToCsvConverter(fieldDelimiter: ';', eol: '\r\n')
        .convert(rows);
  }

  /// Importo in formato italiano senza simbolo né separatore delle migliaia
  /// (es. "1234,56", "-42,80"): non ambiguo per il parser dell'import.
  static String _amount(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}
