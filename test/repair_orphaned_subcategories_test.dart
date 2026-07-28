import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/data/local/seed/repair_orphaned_subcategories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('cancella le sottocategorie rimaste attive sotto una categoria cancellata', () async {
    final deletedCategoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Casa',
            icon: '🏠',
            type: TransactionKind.expense,
            color: 0xFF000000,
            isDeleted: const Value(true),
          ),
        );
    final orphanSubCategoryId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(
            categoryId: deletedCategoryId,
            name: 'Bollette',
          ),
        );

    await repairOrphanedSubCategories(db);

    final orphan = await (db.select(db.subCategories)
          ..where((s) => s.id.equals(orphanSubCategoryId)))
        .getSingle();
    expect(orphan.isDeleted, isTrue);
  });

  test('non tocca le sottocategorie di una categoria ancora attiva', () async {
    final activeCategoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Spesa',
            icon: '🛒',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );
    final subCategoryId = await db.into(db.subCategories).insert(
          SubCategoriesCompanion.insert(
            categoryId: activeCategoryId,
            name: 'Supermercato',
          ),
        );

    await repairOrphanedSubCategories(db);

    final subCategory = await (db.select(db.subCategories)
          ..where((s) => s.id.equals(subCategoryId)))
        .getSingle();
    expect(subCategory.isDeleted, isFalse);
  });

  test('nessuna categoria cancellata: non fa nulla', () async {
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: 'Spesa',
            icon: '🛒',
            type: TransactionKind.expense,
            color: 0xFF000000,
          ),
        );

    // Non deve lanciare né toccare righe: se ci fosse un bug che tenta di
    // aggiornare con una lista di id vuota, questo test lo scoprirebbe.
    await repairOrphanedSubCategories(db);
  });
}
