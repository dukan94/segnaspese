import 'package:drift/drift.dart';
import '../database/app_database.dart';

/// Regole di classificazione di default (v. progettazione, sezione
/// "Regole di classificazione"). Sono un punto di partenza: l'utente può
/// modificarle o cancellarle liberamente dalla schermata Impostazioni,
/// non sono hardcoded nel comportamento dell'app.
Future<void> seedDefaultMerchantRules(AppDatabase db) async {
  final existingRules = await db.select(db.merchantRules).get();
  if (existingRules.isNotEmpty) return;

  final categories = await db.select(db.categories).get();
  int categoryIdByName(String name) =>
      categories.firstWhere((c) => c.name == name).id;

  final subCategories = await db.select(db.subCategories).get();
  int? subCategoryIdByName(String name) {
    final match = subCategories.where((s) => s.name == name);
    return match.isEmpty ? null : match.first.id;
  }

  final casaId = categoryIdByName('Casa');
  final spesaId = categoryIdByName('Spesa');
  final fuoriCasaId = categoryIdByName('Fuori Casa');
  final veicoliId = categoryIdByName('Veicoli & Trasporti');
  final shoppingId = categoryIdByName('Shopping');
  final viaggioId = categoryIdByName('Viaggio');

  final rules = <(String, int, int?)>[
    (r'ESSEL.*', spesaId, subCategoryIdByName('Supermercato')),
    (r'IPERAL.*', spesaId, subCategoryIdByName('Supermercato')),
    (r'EUROSPIN.*', spesaId, subCategoryIdByName('Supermercato')),
    (r'MD.*', spesaId, subCategoryIdByName('Supermercato')),
    (r'LIDL.*', spesaId, subCategoryIdByName('Supermercato')),
    (r'Q8.*', veicoliId, subCategoryIdByName('Carburante')),
    (r'ENI.*', veicoliId, subCategoryIdByName('Carburante')),
    (r'TAMOIL.*', veicoliId, subCategoryIdByName('Carburante')),
    (r'MCDONALD.*', fuoriCasaId, subCategoryIdByName('Ristorante / Uscita')),
    (r'BURGER KING.*', fuoriCasaId, subCategoryIdByName('Ristorante / Uscita')),
    (r'AMAZON.*', shoppingId, subCategoryIdByName('Acquisti Extra / Altro')),
    (r'IKEA.*', casaId, subCategoryIdByName('Arredamento / Elettrodomestici')),
    (r'TRENITALIA.*', viaggioId, subCategoryIdByName('Trasporti di Viaggio')),
    (r'RYANAIR.*', viaggioId, subCategoryIdByName('Voli / Hotel')),
  ];

  await db.transaction(() async {
    for (final (pattern, categoryId, subCategoryId) in rules) {
      await db.into(db.merchantRules).insert(
            MerchantRulesCompanion.insert(
              pattern: pattern,
              categoryId: categoryId,
              subCategoryId: Value(subCategoryId),
              isUserDefined: const Value(false),
            ),
          );
    }
  });
}
