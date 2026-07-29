import 'package:intl/intl.dart';

import '../../domain/entities/transaction_entity.dart';

/// Converte una transazione dell'app nella riga da accodare sul foglio
/// Google "Copia di Spese" (bridge temporaneo, v. CLAUDE.md sezione Admin).
///
/// Ricalca esattamente il pattern con cui Mario compilava il foglio a mano
/// (v. `spese.csv` alla radice del repo, stesse colonne già lette
/// dall'importatore CSV esistente): `Data;Quanto;Sub Categoria;Note;
/// Tipologia Spesa;Categoria;Tipologia`.
class GoogleSheetsRowFormatter {
  GoogleSheetsRowFormatter._();

  static final _dateFormat = DateFormat('dd/MM/yyyy');
  // Spazio normale prima di "€" (non lo spazio non-interrompibile che
  // NumberFormat.currency inserirebbe): è il carattere già usato in
  // spese.csv, verificato byte per byte, così le righe scritte dall'app
  // restano visivamente identiche a quelle compilate a mano finora.
  static final _amountFormat = NumberFormat('#,##0.00', 'it_IT');

  static List<String> format({
    required TransactionEntity transaction,
    required String categoryName,
    required String subCategoryName,
  }) {
    final magnitude = '${_amountFormat.format(transaction.amount)} €';
    // Nel foglio solo il rimborso è scritto con importo negativo: entrate e
    // uscite normali restano positive (a differenza di `signedAmount`, che
    // tratta il rimborso come positivo perché è denaro che rientra).
    final quanto = transaction.isRefund ? '-$magnitude' : magnitude;

    final tipologia = transaction.type == TransactionType.income
        ? 'Entrata'
        : (transaction.isRefund ? 'Rimborso' : 'Spesa');

    return [
      _dateFormat.format(transaction.date),
      quanto,
      subCategoryName,
      transaction.note ?? '',
      transaction.isExtraordinary ? 'Straordinaria' : '',
      categoryName,
      tipologia,
    ];
  }
}
