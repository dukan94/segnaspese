import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
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

  // NOTA sui pattern: il matcher applica queste regex al TESTO GREZZO dello
  // scontrino (v. RuleMatcherService), quindi i pattern sono ancorati con il
  // confine di parola `\b` per evitare falsi positivi. I marchi lunghi usano
  // `\b` come prefisso (es. `\bESSEL` intercetta "ESSELUNGA"); i codici corti
  // e generici (MD, Q8, ENI, LIDL) richiedono la parola intera `\b...\b`, così
  // "ENI" non scatta su parole come "beni"/"generi" né "MD" dentro altre.
  final rules = <(String, int, int?)>[
    (r'\bESSEL', spesaId, subCategoryIdByName('Supermercato')),
    (r'\bIPERAL', spesaId, subCategoryIdByName('Supermercato')),
    (r'\bEUROSPIN', spesaId, subCategoryIdByName('Supermercato')),
    (r'\bMD\b', spesaId, subCategoryIdByName('Supermercato')),
    (r'\bLIDL\b', spesaId, subCategoryIdByName('Supermercato')),
    (r'\bQ8\b', veicoliId, subCategoryIdByName('Carburante')),
    (r'\bENI\b', veicoliId, subCategoryIdByName('Carburante')),
    (r'\bTAMOIL', veicoliId, subCategoryIdByName('Carburante')),
    (r'\bMCDONALD', fuoriCasaId, subCategoryIdByName('Ristorante / Uscita')),
    (r'\bBURGER KING', fuoriCasaId, subCategoryIdByName('Ristorante / Uscita')),
    (r'\bAMAZON', shoppingId, subCategoryIdByName('Acquisti Extra / Altro')),
    (r'\bIKEA\b', casaId, subCategoryIdByName('Arredamento / Elettrodomestici')),
    (r'\bTRENITALIA', viaggioId, subCategoryIdByName('Trasporti di Viaggio')),
    (r'\bRYANAIR', viaggioId, subCategoryIdByName('Voli / Hotel')),
  ];

  await db.transaction(() async {
    for (final (pattern, categoryId, subCategoryId) in rules) {
      await db.into(db.merchantRules).insert(
            MerchantRulesCompanion.insert(
              pattern: pattern,
              categoryId: categoryId,
              subCategoryId: Value(subCategoryId),
              isUserDefined: const Value(false),
              syncId: Value(_defaultRuleSyncId(pattern)),
            ),
          );
    }
  });
}

/// syncId deterministico, stesso motivo di _defaultCategorySyncId in
/// default_categories_seed.dart.
String _defaultRuleSyncId(String pattern) {
  return const Uuid().v5(Namespace.url.value, 'segnaspese:merchant_rule:$pattern');
}
