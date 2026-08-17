// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category_dao.dart';

// ignore_for_file: type=lint
mixin _$CategoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $SubCategoriesTable get subCategories => attachedDatabase.subCategories;
  $SettingsTable get settings => attachedDatabase.settings;
  $RecurringTransactionsTable get recurringTransactions =>
      attachedDatabase.recurringTransactions;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  $MerchantRulesTable get merchantRules => attachedDatabase.merchantRules;
  $BudgetsTable get budgets => attachedDatabase.budgets;
  CategoryDaoManager get managers => CategoryDaoManager(this);
}

class CategoryDaoManager {
  final _$CategoryDaoMixin _db;
  CategoryDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$SubCategoriesTableTableManager get subCategories =>
      $$SubCategoriesTableTableManager(_db.attachedDatabase, _db.subCategories);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db.attachedDatabase, _db.settings);
  $$RecurringTransactionsTableTableManager get recurringTransactions =>
      $$RecurringTransactionsTableTableManager(
          _db.attachedDatabase, _db.recurringTransactions);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db.attachedDatabase, _db.transactions);
  $$MerchantRulesTableTableManager get merchantRules =>
      $$MerchantRulesTableTableManager(_db.attachedDatabase, _db.merchantRules);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db.attachedDatabase, _db.budgets);
}
