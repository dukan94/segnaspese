import '../../entities/transaction_entity.dart';
import '../../services/money_rounding.dart';

/// Costruisce l'entità di un rimborso "quota" da una spesa esistente
/// (M25): l'importo è quello della spesa diviso per [divisor], categoria e
/// sottocategoria ereditate, non modificabili — a differenza del rimborso
/// manuale (`AddTransactionPage(refundOf: ...)`), qui l'utente indica solo
/// il divisore e una nota facoltativa (di solito chi restituisce la quota).
///
/// Logica isolata dalla UI apposta: è l'unica vera logica di business della
/// feature (divisione con arrotondamento + validazione), testabile senza
/// Flutter. Il salvataggio vero passa comunque per `addTransactionProvider`
/// (stessa pipeline del form manuale, incluso il bridge Google Sheets se
/// attivo) — questa classe non tocca il repository.
class BuildSplitRefund {
  const BuildSplitRefund();

  /// [today] arriva dal chiamante (non `DateTime.now()` qui dentro) per
  /// restare puro/testabile. Lancia [ArgumentError] se [divisor] < 2, se
  /// [expense] non ha ancora un id (non salvata), o se non è una spesa
  /// normale (già un rimborso, o un'entrata) — un rimborso di un rimborso
  /// o di un'entrata non ha senso.
  TransactionEntity call({
    required TransactionEntity expense,
    required int divisor,
    required DateTime today,
    String? note,
  }) {
    if (divisor < 2) {
      throw ArgumentError.value(divisor, 'divisor', 'Deve essere almeno 2.');
    }
    if (expense.id == null) {
      throw ArgumentError.value(
          expense, 'expense', 'La spesa da rimborsare deve avere un id.');
    }
    if (expense.type != TransactionType.expense || expense.isRefund) {
      throw ArgumentError.value(expense, 'expense',
          'Si può creare un rimborso con divisore solo da una spesa normale.');
    }

    final trimmedNote = note?.trim();

    return TransactionEntity(
      date: today,
      amount: roundToCents(expense.amount / divisor),
      type: TransactionType.expense,
      categoryId: expense.categoryId,
      subCategoryId: expense.subCategoryId,
      note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
      isRefund: true,
      refundOfId: expense.id,
    );
  }
}
