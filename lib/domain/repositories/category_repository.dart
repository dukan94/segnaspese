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
}
