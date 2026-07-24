import '../../entities/category_entity.dart';
import '../../repositories/category_repository.dart';

class AddSubCategory {
  AddSubCategory(this._repository);

  final CategoryRepository _repository;

  Future<int> call(SubCategoryEntity subCategory) {
    return _repository.addSubCategory(subCategory);
  }
}
