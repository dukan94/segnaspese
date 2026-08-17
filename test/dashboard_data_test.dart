import 'package:finance_app/data/local/database/app_database.dart';
import 'package:finance_app/data/local/database/daos/category_dao.dart';
import 'package:finance_app/data/local/database/tables/categories_table.dart';
import 'package:finance_app/domain/entities/budget_entity.dart';
import 'package:finance_app/domain/entities/transaction_entity.dart';
import 'package:finance_app/presentation/dashboard/dashboard_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `buildDashboardData` (M33): conteggio occorrenze e media per
/// categoria/sottocategoria, al netto dei rimborsi — estratta dal provider
/// apposta per essere testabile senza Riverpod/Drift.
void main() {
  final fixedDate = DateTime(2020, 1, 1);

  Category category({int id = 1, String name = 'Spesa'}) => Category(
        id: id,
        name: name,
        icon: '🛒',
        type: TransactionKind.expense,
        color: 0xFF000000,
        isDefault: false,
        updatedAt: fixedDate,
        isDeleted: false,
        syncId: null,
      );

  SubCategory subCategory(
          {int id = 10, int categoryId = 1, String name = 'Supermercato'}) =>
      SubCategory(
        id: id,
        categoryId: categoryId,
        name: name,
        icon: '🛒',
        updatedAt: fixedDate,
        isDeleted: false,
        syncId: null,
      );

  TransactionEntity expense({
    required double amount,
    int categoryId = 1,
    int? subCategoryId = 10,
    DateTime? date,
    bool isRefund = false,
    bool isExtraordinary = false,
  }) =>
      TransactionEntity(
        date: date ?? DateTime(2026, 3, 15),
        amount: amount,
        type: TransactionType.expense,
        categoryId: categoryId,
        subCategoryId: subCategoryId,
        isRefund: isRefund,
        isExtraordinary: isExtraordinary,
      );

  const params = (year: 2026, month: null, includeExtra: false);

  group('conteggio/media per categoria (M33)', () {
    test(
        'spesa 50€ + rimborso 25€ nella stessa categoria: 1 occorrenza, media 25€ (caso di Mario)',
        () {
      final txns = [
        expense(amount: 50),
        expense(amount: 25, isRefund: true),
      ];
      final data = buildDashboardData(
          txns,
          const [],
          [category()],
          [
            SubCategoryWithCategory(
                subCategory: subCategory(), category: category())
          ],
          params);

      expect(data.byCategory, hasLength(1));
      final slice = data.byCategory.single;
      expect(slice.amount, 25);
      expect(slice.count, 1);
      expect(slice.average, 25);
    });

    test(
        'due spese nella stessa categoria, nessun rimborso: 2 occorrenze, media = somma/2',
        () {
      final txns = [
        expense(amount: 30),
        expense(amount: 20),
      ];
      final data = buildDashboardData(
          txns,
          const [],
          [category()],
          [
            SubCategoryWithCategory(
                subCategory: subCategory(), category: category())
          ],
          params);

      final slice = data.byCategory.single;
      expect(slice.count, 2);
      expect(slice.amount, 50);
      expect(slice.average, 25);
    });

    test('sottocategoria: stesso netting spesa+rimborso della categoria', () {
      final txns = [
        expense(amount: 50),
        expense(amount: 25, isRefund: true),
      ];
      final data = buildDashboardData(
          txns,
          const [],
          [category()],
          [
            SubCategoryWithCategory(
                subCategory: subCategory(), category: category())
          ],
          params);

      final subSlice = data.subByCategory[1]!.single;
      expect(subSlice.count, 1);
      expect(subSlice.amount, 25);
      expect(subSlice.average, 25);
    });

    test('straordinaria esclusa (count e amount) se includeExtra è false', () {
      final txns = [
        expense(amount: 30),
        expense(amount: 999, isExtraordinary: true),
      ];
      final data = buildDashboardData(
          txns,
          const [],
          [category()],
          [
            SubCategoryWithCategory(
                subCategory: subCategory(), category: category())
          ],
          params);

      final slice = data.byCategory.single;
      expect(slice.count, 1);
      expect(slice.amount, 30);
    });

    test('straordinaria inclusa (count e amount) se includeExtra è true', () {
      final txns = [
        expense(amount: 30),
        expense(amount: 70, isExtraordinary: true),
      ];
      final data = buildDashboardData(txns, const [], [
        category()
      ], [
        SubCategoryWithCategory(
            subCategory: subCategory(), category: category())
      ], const (
        year: 2026,
        month: null,
        includeExtra: true
      ));

      final slice = data.byCategory.single;
      expect(slice.count, 2);
      expect(slice.amount, 100);
      expect(slice.average, 50);
    });

    test(
        'categoria con solo un rimborso (nessuna spesa reale nel periodo) non compare',
        () {
      final txns = [expense(amount: 25, isRefund: true)];
      final data = buildDashboardData(
          txns,
          const [],
          [category()],
          [
            SubCategoryWithCategory(
                subCategory: subCategory(), category: category())
          ],
          params);

      expect(data.byCategory, isEmpty);
    });

    test(
        'una transazione fuori dal mese selezionato non entra nel conteggio del mese',
        () {
      final txns = [
        expense(amount: 30, date: DateTime(2026, 3, 15)),
        expense(amount: 999, date: DateTime(2026, 6, 1)),
      ];
      final data = buildDashboardData(txns, const [], [
        category()
      ], [
        SubCategoryWithCategory(
            subCategory: subCategory(), category: category())
      ], const (
        year: 2026,
        month: 3,
        includeExtra: false
      ));

      final slice = data.byCategory.single;
      expect(slice.count, 1);
      expect(slice.amount, 30);
    });

    test(
        'nessuna transazione: nessuna fetta, nessun errore di divisione per zero',
        () {
      final data =
          buildDashboardData(const [], const [], const [], const [], params);
      expect(data.byCategory, isEmpty);
      expect(data.subByCategory, isEmpty);
    });
  });

  group('BudgetEntity fixture di appoggio', () {
    test('accetta lista budget vuota senza errori', () {
      final data = buildDashboardData([
        expense(amount: 10)
      ], const <BudgetEntity>[], [
        category()
      ], [
        SubCategoryWithCategory(
            subCategory: subCategory(), category: category())
      ], params);
      expect(data.totalBudget, 0);
    });
  });
}
