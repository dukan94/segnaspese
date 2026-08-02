import '../../repositories/category_repository.dart';

class MergeSubCategory {
  MergeSubCategory(this._repository);

  final CategoryRepository _repository;

  Future<void> call({required int sourceId, required int targetId}) {
    return _repository.mergeSubCategory(sourceId: sourceId, targetId: targetId);
  }
}
