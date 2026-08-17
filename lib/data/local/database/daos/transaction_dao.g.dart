// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_dao.dart';

// ignore_for_file: type=lint
mixin _$TransactionDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $SubCategoriesTable get subCategories => attachedDatabase.subCategories;
  $RecurringTransactionsTable get recurringTransactions =>
      attachedDatabase.recurringTransactions;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  TransactionDaoManager get managers => TransactionDaoManager(this);
}

class TransactionDaoManager {
  final _$TransactionDaoMixin _db;
  TransactionDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$SubCategoriesTableTableManager get subCategories =>
      $$SubCategoriesTableTableManager(_db.attachedDatabase, _db.subCategories);
  $$RecurringTransactionsTableTableManager get recurringTransactions =>
      $$RecurringTransactionsTableTableManager(
          _db.attachedDatabase, _db.recurringTransactions);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db.attachedDatabase, _db.transactions);
}
