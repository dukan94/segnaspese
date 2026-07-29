import 'dart:async';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/categories_table.dart';
import '../tables/settings_table.dart';
import '../tables/subcategories_table.dart';

part 'category_dao.g.dart';

/// Combina due stream in uno che riemette ogni volta che UNO dei due produce
/// un valore nuovo, usando l'ultimo valore noto dell'altro.
///
/// Serve perché gli stream di categorie/sottocategorie riordinabili (v.
/// [CategoryDao.watchByType] e affini) sono costruiti su una query che tocca
/// solo le tabelle Categories/SubCategories: Drift invalida uno stream in
/// base alle sole tabelle referenziate dalla query, quindi un cambio
/// nell'ordine salvato — che vive nella tabella Settings, letta a parte —
/// non lo faceva ripartire (bug osservato: l'ordine si aggiornava solo al
/// riavvio dell'app, mai a caldo dopo un riordino). Combinando i due stream,
/// un cambiamento in uno qualsiasi dei due fa ricalcolare il risultato.
Stream<R> _combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? latestA;
  B? latestB;
  var hasA = false, hasB = false;

  void emitIfReady() {
    if (hasA && hasB) controller.add(combine(latestA as A, latestB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((value) {
        latestA = value;
        hasA = true;
        emitIfReady();
      }, onError: controller.addError);
      subB = b.listen((value) {
        latestB = value;
        hasB = true;
        emitIfReady();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

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

  /// Osserva l'intera tabella Settings (poche righe in tutto: temi, chiavi
  /// API, ordine di categorie/sottocategorie — va benissimo osservarla per
  /// intero). Serve a far reagire [watchByType]/[watchSubCategories]/
  /// [watchSubCategoriesForType] anche ai soli cambi dell'ordine salvato:
  /// v. commento su [_combineLatest2] per il perché non basterebbe il
  /// `.watch()` sulla sola query di categorie/sottocategorie.
  Stream<Map<String, String>> _watchSettingsMap() {
    return select(settings).watch().map((rows) => {for (final r in rows) r.key: r.value});
  }

  List<int> _parseOrder(String? raw) =>
      (raw == null || raw.isEmpty) ? const [] : raw.split(',').map(int.parse).toList();

  Future<void> _writeOrderedIds(String key, List<int> ids) {
    return into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(
        key: key,
        value: ids.join(','),
        updatedAt: Value(DateTime.now()),
      ),
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
    final key = '$_categoryOrderKeyPrefix${type.name}';
    return _combineLatest2(
      query.watch(),
      _watchSettingsMap(),
      (list, settingsMap) => _applyOrder(list, _parseOrder(settingsMap[key]), (c) => c.id),
    );
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
    final key = '$_subCategoryOrderKeyPrefix$categoryId';
    return _combineLatest2(
      query.watch(),
      _watchSettingsMap(),
      (list, settingsMap) => _applyOrder(list, _parseOrder(settingsMap[key]), (s) => s.id),
    );
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

    final categoryOrderKey = '$_categoryOrderKeyPrefix${type.name}';

    return _combineLatest2(
      query.watch(),
      _watchSettingsMap(),
      (rows, settingsMap) {
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

        final categoryOrder = _parseOrder(settingsMap[categoryOrderKey]);
        final orderedCategoryIds =
            _applyOrder(byCategory.keys.toList(), categoryOrder, (id) => id);

        final result = <SubCategoryWithCategory>[];
        for (final categoryId in orderedCategoryIds) {
          final subOrder = _parseOrder(settingsMap['$_subCategoryOrderKeyPrefix$categoryId']);
          result.addAll(
            _applyOrder(byCategory[categoryId]!, subOrder, (i) => i.subCategory.id),
          );
        }
        return result;
      },
    );
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

  Future<Category?> getCategoryById(int id) {
    return (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<SubCategory?> getSubCategoryById(int id) {
    return (select(subCategories)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

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
