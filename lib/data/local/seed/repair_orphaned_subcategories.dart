import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Ripara sottocategorie rimaste attive nonostante la categoria padre sia
/// cancellata: uno stato che il normale flusso di cancellazione non produce
/// mai (`CategoryDao.softDeleteCategory` cancella sempre insieme le
/// sottocategorie), ma che due dispositivi possono creare in combinazione con
/// `dedupeDefaultTaxonomy` durante la sync (es. la cancellazione di una
/// categoria arriva via sync mentre la sottocategoria sopravvissuta al
/// dedupe locale non è quella già cancellata sull'altro dispositivo).
///
/// Eseguita a ogni avvio (v. main.dart, dopo dedupeDefaultTaxonomy): costo
/// trascurabile quando non ci sono sottocategorie orfane, "si ripara da sola"
/// se succede di nuovo per qualunque motivo — stesso principio di
/// dedupe_default_taxonomy.dart.
Future<void> repairOrphanedSubCategories(AppDatabase db) async {
  final deletedCategories =
      await (db.select(db.categories)..where((c) => c.isDeleted.equals(true))).get();
  if (deletedCategories.isEmpty) return;
  final deletedIds = deletedCategories.map((c) => c.id).toList();

  final now = DateTime.now();
  await (db.update(db.subCategories)
        ..where((s) => s.categoryId.isIn(deletedIds) & s.isDeleted.equals(false)))
      .write(SubCategoriesCompanion(isDeleted: const Value(true), updatedAt: Value(now)));
}
