import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/local/database/daos/category_dao.dart';
import '../../data/local/database/tables/categories_table.dart';
import '../../data/repositories_impl/category_repository_impl.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/usecases/category/add_category.dart';
import '../../domain/usecases/category/add_subcategory.dart';
import '../../domain/usecases/category/delete_category.dart';
import '../../domain/usecases/category/delete_subcategory.dart';
import '../../domain/usecases/category/reorder_categories.dart';
import '../../domain/usecases/category/reorder_subcategories.dart';
import '../../domain/usecases/category/update_category.dart';
import '../../domain/usecases/category/update_subcategory.dart';
import 'database_provider.dart';

final categoryDaoProvider = Provider<CategoryDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.categoryDao;
});

/// Tutte le categorie non cancellate (usato per le lookup id → categoria,
/// es. nelle "Ultime operazioni" della Home).
final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryDaoProvider).watchAll();
});

/// Categorie filtrate per tipo (income/expense), per il picker della
/// schermata "Nuova Operazione".
final categoriesByTypeProvider =
    StreamProvider.family<List<Category>, TransactionKind>((ref, type) {
  return ref.watch(categoryDaoProvider).watchByType(type);
});

/// Sottocategorie di una categoria specifica.
final subCategoriesProvider =
    StreamProvider.family<List<SubCategory>, int>((ref, categoryId) {
  return ref.watch(categoryDaoProvider).watchSubCategories(categoryId);
});

/// Tutte le sottocategorie disponibili per un tipo (income/expense), con la
/// rispettiva categoria padre — usato dal picker unico della schermata
/// "Nuova Operazione" (v. [SubCategoryWithCategory]).
final subCategoriesForTypeProvider =
    StreamProvider.family<List<SubCategoryWithCategory>, TransactionKind>((ref, type) {
  return ref.watch(categoryDaoProvider).watchSubCategoriesForType(type);
});

// --- Scrittura (Milestone M2: gestione categorie da UI) ---

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl(ref.watch(categoryDaoProvider));
});

final addCategoryProvider = Provider<AddCategory>((ref) {
  return AddCategory(ref.watch(categoryRepositoryProvider));
});

final updateCategoryProvider = Provider<UpdateCategory>((ref) {
  return UpdateCategory(ref.watch(categoryRepositoryProvider));
});

final deleteCategoryProvider = Provider<DeleteCategory>((ref) {
  return DeleteCategory(ref.watch(categoryRepositoryProvider));
});

final addSubCategoryProvider = Provider<AddSubCategory>((ref) {
  return AddSubCategory(ref.watch(categoryRepositoryProvider));
});

final updateSubCategoryProvider = Provider<UpdateSubCategory>((ref) {
  return UpdateSubCategory(ref.watch(categoryRepositoryProvider));
});

final deleteSubCategoryProvider = Provider<DeleteSubCategory>((ref) {
  return DeleteSubCategory(ref.watch(categoryRepositoryProvider));
});

final reorderCategoriesProvider = Provider<ReorderCategories>((ref) {
  return ReorderCategories(ref.watch(categoryRepositoryProvider));
});

final reorderSubCategoriesProvider = Provider<ReorderSubCategories>((ref) {
  return ReorderSubCategories(ref.watch(categoryRepositoryProvider));
});
