import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/categories_table.dart';
import '../tables/settings_table.dart';
import '../tables/subcategories_table.dart';

part 'category_dao.g.dart';

/// Sottocategoria abbinata alla sua categoria padre: la selezione nella
/// schermata "Nuova Operazione" avviene direttamente sulla sottocategoria
/// (più specifica), e la categoria viene derivata automaticamente da qui,
/// invece di essere scelta separatamente.
class SubCategoryWithCategory {
  const SubCategoryWithCategory({required this.subCategory, required this.category});

  final SubCategory subCategory;
  final Category category;
}

/// Accesso a categorie/sottocategorie: query di lettura (usate anche dal
/// picker sottocategoria di "Nuova Operazione" e dalla Home) e CRUD completo
/// per la gestione categorie personalizzate (Milestone M2), incluso il
/// riordino manuale (drag & drop).
///
/// L'ordine manuale scelto dall'utente è salvato nella tabella `Settings`
/// (già esistente, chiave/valore) come elenco di id separati da virgola —
/// niente nuove colonne né migrazioni di schema su Categories/SubCategories.
/// Le categorie/sottocategorie non ancora presenti in un elenco salvato
/// (es. appena create) vengono semplicemente aggiunte in coda.
@DriftAccessor(tables: [Categories, SubCategories, Settings])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  static const _categoryOrderKeyPrefix = 'category_order_';
  static const _subCategoryOrderKeyPrefix = 'subcategory_order_';

  Future<List<int>> _readOrderedIds(String key) async {
    final row = await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull();
    if (row == null || row.value.isEmpty) return const [];
    return row.value.split(',').map(int.parse).toList();
  }

  Future<void> _writeOrderedIds(String key, List<int> ids) {
    return into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: ids.join(',')),
    );
  }

  /// Riordina [items] secondo [orderedIds]; gli elementi non presenti in
  /// [orderedIds] (es. appena creati) restano in coda, nell'ordine in cui
  /// arrivano da [items].
  List<T> _applyOrder<T>(List<T> items, List<int> orderedIds, int Function(T) idOf) {
    if (orderedIds.isEmpty) return items;
    final remaining = {for (final item in items) idOf(item): item};
    final ordered = <T>[
      for (final id in orderedIds)
        if (remaining.remove(id) case final item?) item,
    ];
    ordered.addAll(remaining.values);
    return ordered;
  }

  /// Tutte le categorie non cancellate, per tipo (income/expense), nell'ordine
  /// manuale scelto dall'utente (v. [reorderCategories]).
  Stream<List<Category>> watchByType(TransactionKind type) {
    final query = select(categories)
      ..where((c) => c.isDeleted.equals(false) & c.type.equalsValue(type))
      ..orderBy([(c) => OrderingTerm.asc(c.id)]);
    return query.watch().asyncMap((list) async {
      final order = await _readOrderedIds('$_categoryOrderKeyPrefix${type.name}');
      return _applyOrder(list, order, (c) => c.id);
    });
  }

  /// Tutte le categorie non cancellate (utile per le lookup id → categoria
  /// nelle liste, es. ultime operazioni in Home). Ordine non rilevante qui.
  Stream<List<Category>> watchAll() {
    final query = select(categories)
      ..where((c) => c.isDeleted.equals(false))
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch();
  }

  /// Sottocategorie di una categoria, non cancellate, nell'ordine manuale
  /// scelto dall'utente (v. [reorderSubCategories]).
  Stream<List<SubCategory>> watchSubCategories(int categoryId) {
    final query = select(subCategories)
      ..where((s) => s.isDeleted.equals(false) & s.categoryId.equals(categoryId))
      ..orderBy([(s) => OrderingTerm.asc(s.id)]);
    return query.watch().asyncMap((list) async {
      final order = await _readOrderedIds('$_subCategoryOrderKeyPrefix$categoryId');
      return _applyOrder(list, order, (s) => s.id);
    });
  }

  /// Tutte le sottocategorie disponibili per un tipo (income/expense), ognuna
  /// abbinata alla propria categoria padre, raggruppate per categoria
  /// nell'ordine manuale di categorie e sottocategorie. Alimenta il picker
  /// unico "sottocategoria" nella schermata "Nuova Operazione".
  Stream<List<SubCategoryWithCategory>> watchSubCategoriesForType(
    TransactionKind type,
  ) {
    final query = select(subCategories).join([
      innerJoin(categories, categories.id.equalsExp(subCategories.categoryId)),
    ])
      ..where(
        subCategories.isDeleted.equals(false) &
            categories.isDeleted.equals(false) &
            categories.type.equalsValue(type),
      )
      ..orderBy([
        OrderingTerm.asc(categories.id),
        OrderingTerm.asc(subCategories.id),
      ]);

    return query.watch().asyncMap((rows) async {
      final items = rows
          .map(
            (row) => SubCategoryWithCategory(
              subCategory: row.readTable(subCategories),
              category: row.readTable(categories),
            ),
          )
          .toList();

      final byCategory = <int, List<SubCategoryWithCategory>>{};
      for (final item in items) {
        byCategory.putIfAbsent(item.category.id, () => []).add(item);
      }

      final categoryOrder = await _readOrderedIds('$_categoryOrderKeyPrefix${type.name}');
      final orderedCategoryIds =
          _applyOrder(byCategory.keys.toList(), categoryOrder, (id) => id);

      final result = <SubCategoryWithCategory>[];
      for (final categoryId in orderedCategoryIds) {
        final subOrder = await _readOrderedIds('$_subCategoryOrderKeyPrefix$categoryId');
        result.addAll(
          _applyOrder(byCategory[categoryId]!, subOrder, (i) => i.subCategory.id),
        );
      }
      return result;
    });
  }

  /// Salva l'ordine manuale delle categorie di tipo [type] (drag & drop
  /// nella schermata di gestione).
  Future<void> reorderCategories(TransactionKind type, List<int> orderedIds) {
    return _writeOrderedIds('$_categoryOrderKeyPrefix${type.name}', orderedIds);
  }

  /// Salva l'ordine manuale delle sottocategorie di [categoryId].
  Future<void> reorderSubCategories(int categoryId, List<int> orderedIds) {
    return _writeOrderedIds('$_subCategoryOrderKeyPrefix$categoryId', orderedIds);
  }

  // --- Scrittura CRUD (Milestone M2: gestione categorie da UI) ---

  Future<int> insertCategory(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  Future<bool> updateCategory(CategoriesCompanion entry) {
    return update(categories).replace(entry);
  }

  /// Soft delete della categoria e, in cascata, di tutte le sue
  /// sottocategorie (altrimenti resterebbero orfane ma ancora selezionabili
  /// in teoria, dato che il vincolo di FK non viene verificato a runtime).
  Future<void> softDeleteCategory(int id) async {
    final now = DateTime.now();
    await transaction(() async {
      await (update(subCategories)..where((s) => s.categoryId.equals(id))).write(
        SubCategoriesCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
      await (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(isDeleted: const Value(true), updatedAt: Value(now)),
      );
    });
  }

  Future<int> insertSubCategory(SubCategoriesCompanion entry) {
    return into(subCategories).insert(entry);
  }

  Future<bool> updateSubCategory(SubCategoriesCompanion entry) {
    return update(subCategories).replace(entry);
  }

  Future<int> softDeleteSubCategory(int id) {
    return (update(subCategories)..where((s) => s.id.equals(id))).write(
      SubCategoriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
