import '../../repositories/category_repository.dart';

class DeleteSubCategory {
  DeleteSubCategory(this._repository);

  final CategoryRepository _repository;

  Future<void> call(int subCategoryId) {
    return _repository.deleteSubCategory(subCategoryId);
  }
}
