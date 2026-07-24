import '../../entities/transaction_entity.dart';
import '../../repositories/category_repository.dart';

/// Salva il nuovo ordine (drag & drop) delle categorie di un tipo.
class ReorderCategories {
  ReorderCategories(this._repository);

  final CategoryRepository _repository;

  Future<void> call(TransactionType type, List<int> orderedCategoryIds) {
    return _repository.reorderCategories(type, orderedCategoryIds);
  }
}
