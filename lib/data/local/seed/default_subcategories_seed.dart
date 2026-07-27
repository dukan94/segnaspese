import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';

/// Sottocategorie di default, seedate al primo avvio subito dopo le
/// categorie principali (v. seedDefaultCategories, deve essere chiamata
/// prima di questa). Corrispondono alla tassonomia fornita dall'utente:
/// ogni categoria ha sottocategorie specifiche (nessuna sottocategoria
/// "generica" col nome del padre), sufficienti a coprire la selezione
/// obbligatoria nella schermata "Nuova Operazione".
Future<void> seedDefaultSubCategories(AppDatabase db) async {
  final existing = await db.select(db.subCategories).get();
  if (existing.isNotEmpty) return; // già inizializzato

  final categories = await db.select(db.categories).get();
  int categoryIdByName(String name) =>
      categories.firstWhere((c) => c.name == name).id;

  // (categoria padre, nome sottocategoria, icona)
  final subCategories = <(String, String, String)>[
    // --- Uscite ---
    ('Casa', 'Affitto / Mutuo', '🏠'),
    ('Casa', 'Bollette', '🧾'),
    ('Casa', 'Pulizie / Manutenzione', '🧹'),
    ('Casa', 'Tasse', '💶'),
    ('Casa', 'Arredamento / Elettrodomestici', '🛋️'),

    ('Spesa', 'Supermercato', '🛒'),
    ('Spesa', 'Mercato / Negozi Alimentari', '🥖'),

    ('Fuori Casa', 'Colazione / Bar', '🥐'),
    ('Fuori Casa', 'Ristorante / Uscita', '🍔'),
    ('Fuori Casa', 'Delivery', '🍕'),

    ('Veicoli & Trasporti', 'Carburante', '⛽'),
    ('Veicoli & Trasporti', 'Assicurazione', '🛡️'),
    ('Veicoli & Trasporti', 'Manutenzione', '🧼'),
    ('Veicoli & Trasporti', 'Bollo', '✉️'),
    ('Veicoli & Trasporti', 'Multa', '💸'),
    ('Veicoli & Trasporti', 'Rata / Finanziamento', '🧧'),
    ('Veicoli & Trasporti', 'Mezzi Pubblici / Taxi', '🚇'),

    ('Salute', 'Medico / Farmaci', '💊'),
    ('Salute', 'Dentista / Specialisti', '🦷'),

    ('Self Care', 'Parrucchiere / Estetista', '💆'),
    ('Self Care', 'Cura Personale', '💅'),

    ('Shopping', 'Abbigliamento', '👗'),
    ('Shopping', 'Tecnologia', '💻'),
    ('Shopping', 'Regalo (fatto)', '🎁'),
    ('Shopping', 'Acquisti Extra / Altro', '📦'),

    ('Tempo Libero', 'Svago (cinema, eventi)', '🎬'),
    ('Tempo Libero', 'Hobby', '📸'),
    ('Tempo Libero', 'Abbonamenti', '🖊️'),
    ('Tempo Libero', 'Sport / Palestra', '🏌️'),

    ('Viaggio', 'Voli / Hotel', '✈️'),
    ('Viaggio', 'Trasporti di Viaggio', '🧳'),

    // --- Entrate ---
    ('Stipendio', 'Stipendio', '💳'),
    ('Stipendio', 'Stipendio Extra', '💳'),
    ('Stipendio', 'Guadagno Extra', '💳'),

    ('Regalo', 'Regalo (ricevuto)', '🎁'),
  ];

  await db.transaction(() async {
    for (final (categoryName, name, icon) in subCategories) {
      await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(
              categoryId: categoryIdByName(categoryName),
              name: name,
              icon: Value(icon),
              syncId: Value(_defaultSubCategorySyncId(categoryName, name)),
            ),
          );
    }
  });
}

/// syncId deterministico, stesso motivo di _defaultCategorySyncId in
/// default_categories_seed.dart.
String _defaultSubCategorySyncId(String categoryName, String name) {
  return const Uuid().v5(Namespace.url.value, 'segnaspese:subcategory:$categoryName:$name');
}
