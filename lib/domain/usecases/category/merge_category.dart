import '../../repositories/category_repository.dart';

class MergeCategory {
  MergeCategory(this._repository);

  final CategoryRepository _repository;

  Future<void> call({required int sourceId, required int targetId}) {
    return _repository.mergeCategory(sourceId: sourceId, targetId: targetId);
  }
}
