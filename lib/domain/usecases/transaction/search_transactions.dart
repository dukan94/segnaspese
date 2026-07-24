import '../../entities/transaction_entity.dart';
import '../../repositories/transaction_repository.dart';

/// Parametri di ricerca opzionali (tutti combinabili in AND).
class SearchTransactionsParams {
  const SearchTransactionsParams({
    this.merchantQuery,
    this.note,
    this.categoryId,
    this.amount,
    this.date,
  });

  final String? merchantQuery;
  final String? note;
  final int? categoryId;
  final double? amount;
  final DateTime? date;
}

/// Ricerca transazioni per negozio/categoria/importo/note/data (v. Milestone
/// M6 per la schermata dedicata; il repository/DAO sono già pronti da M1).
class SearchTransactions {
  SearchTransactions(this._repository);

  final TransactionRepository _repository;

  Future<List<TransactionEntity>> call(SearchTransactionsParams params) {
    return _repository.search(
      merchantQuery: params.merchantQuery,
      note: params.note,
      categoryId: params.categoryId,
      amount: params.amount,
      date: params.date,
    );
  }
}
