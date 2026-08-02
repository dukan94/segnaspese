import '../../domain/entities/category_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../local/database/daos/category_dao.dart';
import '../mappers/category_mapper.dart';
import '../mappers/transaction_mapper.dart' show TransactionTypeMapper;

/// Implementazione concreta di [CategoryRepository], basata su Drift.
class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._dao);

  final CategoryDao _dao;

  @override
  Stream<List<CategoryEntity>> watchAll() {
    return _dao.watchAll().map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Stream<List<CategoryEntity>> watchByType(TransactionType type) {
    return _dao
        .watchByType(type.toDrift())
        .map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Stream<List<SubCategoryEntity>> watchSubCategories(int categoryId) {
    return _dao
        .watchSubCategories(categoryId)
        .map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  @override
  Future<int> addCategory(CategoryEntity category) {
    return _dao.insertCategory(category.toInsertCompanion());
  }

  @override
  Future<void> updateCategory(CategoryEntity category) async {
    await _dao.updateCategory(category.toUpdateCompanion());
  }

  @override
  Future<void> deleteCategory(int id) async {
    await _dao.softDeleteCategory(id);
  }

  @override
  Future<int> addSubCategory(SubCategoryEntity subCategory) {
    return _dao.insertSubCategory(subCategory.toInsertCompanion());
  }

  @override
  Future<void> updateSubCategory(SubCategoryEntity subCategory) async {
    await _dao.updateSubCategory(subCategory.toUpdateCompanion());
  }

  @override
  Future<void> deleteSubCategory(int id) async {
    await _dao.softDeleteSubCategory(id);
  }

  @override
  Future<void> reorderCategories(TransactionType type, List<int> orderedCategoryIds) {
    return _dao.reorderCategories(type.toDrift(), orderedCategoryIds);
  }

  @override
  Future<void> reorderSubCategories(int categoryId, List<int> orderedSubCategoryIds) {
    return _dao.reorderSubCategories(categoryId, orderedSubCategoryIds);
  }

  @override
  Future<bool> categoryHasBlockingSubCategories(int categoryId) {
    return _dao.categoryHasBlockingSubCategories(categoryId);
  }

  @override
  Future<CategoryMergeImpact> categoryMergeImpact(int categoryId) {
    return _dao.categoryMergeImpact(categoryId);
  }

  @override
  Future<CategoryMergeImpact> subCategoryMergeImpact(int subCategoryId) {
    return _dao.subCategoryMergeImpact(subCategoryId);
  }

  @override
  Future<void> mergeCategory({required int sourceId, required int targetId}) {
    return _dao.mergeCategoryInto(sourceId: sourceId, targetId: targetId);
  }

  @override
  Future<void> mergeSubCategory({required int sourceId, required int targetId}) {
    return _dao.mergeSubCategoryInto(sourceId: sourceId, targetId: targetId);
  }
}
