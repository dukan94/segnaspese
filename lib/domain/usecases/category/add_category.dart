import '../../entities/category_entity.dart';
import '../../repositories/category_repository.dart';

class AddCategory {
  AddCategory(this._repository);

  final CategoryRepository _repository;

  Future<int> call(CategoryEntity category) {
    return _repository.addCategory(category);
  }
}
