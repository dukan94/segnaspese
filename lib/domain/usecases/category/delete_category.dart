import '../../repositories/category_repository.dart';

/// Elimina (soft delete) una categoria e, in cascata, tutte le sue
/// sottocategorie (v. [CategoryRepository.deleteCategory]).
class DeleteCategory {
  DeleteCategory(this._repository);

  final CategoryRepository _repository;

  Future<void> call(int categoryId) {
    return _repository.deleteCategory(categoryId);
  }
}
