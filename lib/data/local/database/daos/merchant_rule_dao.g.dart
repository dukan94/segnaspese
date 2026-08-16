// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merchant_rule_dao.dart';

// ignore_for_file: type=lint
mixin _$MerchantRuleDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $SubCategoriesTable get subCategories => attachedDatabase.subCategories;
  $MerchantRulesTable get merchantRules => attachedDatabase.merchantRules;
  MerchantRuleDaoManager get managers => MerchantRuleDaoManager(this);
}

class MerchantRuleDaoManager {
  final _$MerchantRuleDaoMixin _db;
  MerchantRuleDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$SubCategoriesTableTableManager get subCategories =>
      $$SubCategoriesTableTableManager(_db.attachedDatabase, _db.subCategories);
  $$MerchantRulesTableTableManager get merchantRules =>
      $$MerchantRulesTableTableManager(_db.attachedDatabase, _db.merchantRules);
}
