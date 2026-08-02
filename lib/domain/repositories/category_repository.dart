import '../entities/category_entity.dart';
import '../entities/transaction_entity.dart';

/// Contratto che il layer Data deve implementare per categorie e
/// sottocategorie. Il layer Domain/Presentation dipende solo da questa
/// interfaccia, mai dall'implementazione concreta (Drift).
abstract class CategoryRepository {
  Stream<List<CategoryEntity>> watchAll();

  Stream<List<CategoryEntity>> watchByType(TransactionType type);

  Stream<List<SubCategoryEntity>> watchSubCategories(int categoryId);

  Future<int> addCategory(CategoryEntity category);

  Future<void> updateCategory(CategoryEntity category);

  /// Soft delete della categoria. Elimina in cascata (soft delete) anche
  /// tutte le sue sottocategorie, per evitare di lasciare sottocategorie
  /// "orfane" ancora selezionabili senza una categoria padre attiva.
  Future<void> deleteCategory(int id);

  Future<int> addSubCategory(SubCategoryEntity subCategory);

  Future<void> updateSubCategory(SubCategoryEntity subCategory);

  Future<void> deleteSubCategory(int id);

  /// Salva l'ordine manuale (drag & drop) delle categorie di tipo [type].
  Future<void> reorderCategories(TransactionType type, List<int> orderedCategoryIds);

  /// Salva l'ordine manuale (drag & drop) delle sottocategorie di
  /// [categoryId].
  Future<void> reorderSubCategories(int categoryId, List<int> orderedSubCategoryIds);

  /// True se [categoryId] ha ancora sottocategorie attive referenziate da
  /// transazioni/regole/ricorrenze non cancellate: va prima risolto quello
  /// (unendole o eliminandole) prima di poter unire la categoria stessa.
  Future<bool> categoryHasBlockingSubCategories(int categoryId);

  /// Quante righe verrebbero spostate unendo [categoryId] in un'altra
  /// categoria, per il dialog di conferma.
  Future<CategoryMergeImpact> categoryMergeImpact(int categoryId);

  /// Quante righe verrebbero spostate unendo [subCategoryId] in un'altra
  /// sottocategoria, per il dialog di conferma.
  Future<CategoryMergeImpact> subCategoryMergeImpact(int subCategoryId);

  /// Sposta transazioni/regole/budget/ricorrenze di [sourceId] su
  /// [targetId], poi elimina (soft delete) la categoria [sourceId].
  /// Fallisce se [sourceId] ha ancora sottocategorie attive con dati
  /// collegati (v. [categoryHasBlockingSubCategories]).
  Future<void> mergeCategory({required int sourceId, required int targetId});

  /// Sposta transazioni/regole/ricorrenze di [sourceId] su [targetId], poi
  /// elimina (soft delete) la sottocategoria [sourceId].
  Future<void> mergeSubCategory({required int sourceId, required int targetId});
}
