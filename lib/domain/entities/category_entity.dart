import 'transaction_entity.dart';

class CategoryEntity {
  final int? id;
  final String name;
  final String icon;
  final TransactionType type;
  final int color;
  final bool isDefault;

  const CategoryEntity({
    this.id,
    required this.name,
    required this.icon,
    required this.type,
    required this.color,
    this.isDefault = false,
  });
}

class SubCategoryEntity {
  final int? id;
  final int categoryId;
  final String name;
  final String icon;

  const SubCategoryEntity({
    this.id,
    required this.categoryId,
    required this.name,
    this.icon = '',
  });
}
