import '../../entities/category_entity.dart';
import '../../repositories/category_repository.dart';

class UpdateSubCategory {
  UpdateSubCategory(this._repository);

  final CategoryRepository _repository;

  Future<void> call(SubCategoryEntity subCategory) {
    return _repository.updateSubCategory(subCategory);
  }
}
