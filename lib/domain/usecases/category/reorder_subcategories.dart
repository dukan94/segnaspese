import '../../repositories/category_repository.dart';

/// Salva il nuovo ordine (drag & drop) delle sottocategorie di una categoria.
class ReorderSubCategories {
  ReorderSubCategories(this._repository);

  final CategoryRepository _repository;

  Future<void> call(int categoryId, List<int> orderedSubCategoryIds) {
    return _repository.reorderSubCategories(categoryId, orderedSubCategoryIds);
  }
}
