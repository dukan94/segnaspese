import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/category_entity.dart';
import '../local/database/app_database.dart';
import 'transaction_mapper.dart' show TransactionKindMapper, TransactionTypeMapper;

/// Conversioni tra le righe Drift (`Category`/`SubCategory`) e le entità di
/// dominio (`CategoryEntity`/`SubCategoryEntity`). Riusa il mapping
/// `TransactionKind` ↔ `TransactionType` già definito in transaction_mapper.
extension CategoryDataMapper on Category {
  CategoryEntity toEntity() {
    return CategoryEntity(
      id: id,
      name: name,
      icon: icon,
      type: type.toDomain(),
      color: color,
      isDefault: isDefault,
    );
  }
}

extension CategoryEntityMapper on CategoryEntity {
  CategoriesCompanion toInsertCompanion() {
    return CategoriesCompanion.insert(
      name: name,
      icon: icon,
      type: type.toDrift(),
      color: color,
      isDefault: Value(isDefault),
      updatedAt: Value(DateTime.now()),
      syncId: Value(const Uuid().v4()),
    );
  }

  CategoriesCompanion toUpdateCompanion() {
    assert(id != null, 'id richiesto per aggiornare una categoria esistente');
    return CategoriesCompanion(
      id: Value(id!),
      name: Value(name),
      icon: Value(icon),
      type: Value(type.toDrift()),
      color: Value(color),
      isDefault: Value(isDefault),
      updatedAt: Value(DateTime.now()),
    );
  }
}

extension SubCategoryDataMapper on SubCategory {
  SubCategoryEntity toEntity() {
    return SubCategoryEntity(
      id: id,
      categoryId: categoryId,
      name: name,
      icon: icon,
    );
  }
}

extension SubCategoryEntityMapper on SubCategoryEntity {
  SubCategoriesCompanion toInsertCompanion() {
    return SubCategoriesCompanion.insert(
      categoryId: categoryId,
      name: name,
      icon: Value(icon),
      updatedAt: Value(DateTime.now()),
      syncId: Value(const Uuid().v4()),
    );
  }

  SubCategoriesCompanion toUpdateCompanion() {
    assert(id != null, 'id richiesto per aggiornare una sottocategoria esistente');
    return SubCategoriesCompanion(
      id: Value(id!),
      categoryId: Value(categoryId),
      name: Value(name),
      icon: Value(icon),
      updatedAt: Value(DateTime.now()),
    );
  }
}
