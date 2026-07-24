import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../database/tables/categories_table.dart';

/// Categorie di default proposte al primo avvio, secondo la tassonomia
/// fornita dall'utente. Le sottocategorie corrispondenti vengono seedate
/// subito dopo, in `seedDefaultSubCategories`
/// (v. default_subcategories_seed.dart, chiamato in sequenza da main.dart).
///
/// L'ordine di inserimento definisce l'ordine iniziale mostrato nelle liste
/// (le categorie sono poi riordinabili manualmente dall'utente).
Future<void> seedDefaultCategories(AppDatabase db) async {
  final existing = await db.select(db.categories).get();
  if (existing.isNotEmpty) return; // già inizializzato

  final incomeCategories = <(String, String, int)>[
    ('Stipendio', '💳', 0xFF2E7D5B),
    ('Regalo', '🎁', 0xFF9BC1A8),
    ('Rimborsi', '🔄', 0xFF6FA287),
  ];

  final expenseCategories = <(String, String, int)>[
    ('Casa', '🏠', 0xFF8D6E63),
    ('Spesa', '🛒', 0xFF4C8C63),
    ('Fuori Casa', '🍔', 0xFFEF6C00),
    ('Veicoli & Trasporti', '🚗', 0xFF546E7A),
    ('Salute', '💊', 0xFFC62828),
    ('Self Care', '💆', 0xFFAD1457),
    ('Shopping', '🛍️', 0xFF4527A0),
    ('Tempo Libero', '⛷️', 0xFF1976D2),
    ('Viaggio', '✈️', 0xFF00838F),
  ];

  await db.transaction(() async {
    for (final (name, icon, color) in incomeCategories) {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: name,
              icon: icon,
              type: TransactionKind.income,
              color: color,
              isDefault: const Value(true),
            ),
          );
    }
    for (final (name, icon, color) in expenseCategories) {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: name,
              icon: icon,
              type: TransactionKind.expense,
              color: color,
              isDefault: const Value(true),
            ),
          );
    }
  });
}
