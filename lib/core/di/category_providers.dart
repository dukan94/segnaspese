import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database/app_database.dart';
import '../../data/local/database/daos/category_dao.dart';
import '../../data/local/database/tables/categories_table.dart';
import '../../data/repositories_impl/category_repository_impl.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../../domain/usecases/category/add_category.dart';
import '../../domain/usecases/category/add_subcategory.dart';
import '../../domain/usecases/category/delete_category.dart';
import '../../domain/usecases/category/delete_subcategory.dart';
import '../../domain/usecases/category/merge_category.dart';
import '../../domain/usecases/category/merge_subcategory.dart';
import '../../domain/usecases/category/reorder_categories.dart';
import '../../domain/usecases/category/reorder_subcategories.dart';
import '../../domain/usecases/category/update_category.dart';
import '../../domain/usecases/category/update_subcategory.dart';
import 'database_provider.dart';
import 'sync_providers.dart';

/// Logga un fallimento della sync scatenata dopo un salvataggio (M58) —
/// stesso pattern fire-and-forget di `transaction_providers.dart` (M32) e
/// `budget_providers.dart` (M56), mai mostrato all'utente.
void _logPostSaveSyncError(Object error, StackTrace stackTrace) {
  debugPrint('Sync Turso fallita (dopo salvataggio categoria): $error\n$stackTrace');
}

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
    StreamProvider.autoDispose.family<List<SubCategory>, int>((ref, categoryId) {
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

/// M58: dopo il salvataggio locale lancia anche una sync Turso in
/// background — stesso trattamento di transazioni (M32) e budget (M56),
/// mancante qui da sempre. Vale per tutte le scritture su categorie/
/// sottocategorie tranne il riordino (v. [reorderCategoriesProvider]).
final addCategoryProvider =
    Provider<Future<int> Function(CategoryEntity)>((ref) {
  final useCase = AddCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (category) async {
    final id = await useCase.call(category);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
    return id;
  };
});

/// M58: v. [addCategoryProvider].
final updateCategoryProvider =
    Provider<Future<void> Function(CategoryEntity)>((ref) {
  final useCase = UpdateCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (category) async {
    await useCase.call(category);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addCategoryProvider].
final deleteCategoryProvider = Provider<Future<void> Function(int)>((ref) {
  final useCase = DeleteCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (categoryId) async {
    await useCase.call(categoryId);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addCategoryProvider].
final addSubCategoryProvider =
    Provider<Future<int> Function(SubCategoryEntity)>((ref) {
  final useCase = AddSubCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (subCategory) async {
    final id = await useCase.call(subCategory);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
    return id;
  };
});

/// M58: v. [addCategoryProvider].
final updateSubCategoryProvider =
    Provider<Future<void> Function(SubCategoryEntity)>((ref) {
  final useCase = UpdateSubCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (subCategory) async {
    await useCase.call(subCategory);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addCategoryProvider].
final deleteSubCategoryProvider = Provider<Future<void> Function(int)>((ref) {
  final useCase = DeleteSubCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return (subCategoryId) async {
    await useCase.call(subCategoryId);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// Niente sync dopo il riordino (M58, escluso apposta): l'ordine vive solo
/// in `Settings`, che resta locale (v. `_syncedSettingsKeys` in
/// `turso_sync_service.dart`) — una sync qui non spingerebbe nulla.
final reorderCategoriesProvider = Provider<ReorderCategories>((ref) {
  return ReorderCategories(ref.watch(categoryRepositoryProvider));
});

final reorderSubCategoriesProvider = Provider<ReorderSubCategories>((ref) {
  return ReorderSubCategories(ref.watch(categoryRepositoryProvider));
});

/// M58: v. [addCategoryProvider].
final mergeCategoryProvider = Provider<
    Future<void> Function({required int sourceId, required int targetId})>(
    (ref) {
  final useCase = MergeCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return ({required sourceId, required targetId}) async {
    await useCase.call(sourceId: sourceId, targetId: targetId);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});

/// M58: v. [addCategoryProvider].
final mergeSubCategoryProvider = Provider<
    Future<void> Function({required int sourceId, required int targetId})>(
    (ref) {
  final useCase = MergeSubCategory(ref.watch(categoryRepositoryProvider));
  final syncService = ref.watch(syncServiceProvider);
  return ({required sourceId, required targetId}) async {
    await useCase.call(sourceId: sourceId, targetId: targetId);
    unawaited(syncService.syncNow().catchError(_logPostSaveSyncError));
  };
});
