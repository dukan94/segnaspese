import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import 'default_seed_timestamp.dart';

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
    ('Casa', 'Affitto / Mutuo', 'home'),
    ('Casa', 'Bollette', 'receipt'),
    ('Casa', 'Pulizie / Manutenzione', 'cleaning'),
    ('Casa', 'Tasse', 'euro'),
    ('Casa', 'Arredamento / Elettrodomestici', 'sofa'),

    ('Spesa', 'Supermercato', 'cart'),
    ('Spesa', 'Mercato / Negozi Alimentari', 'bakery'),

    ('Fuori Casa', 'Colazione / Bar', 'coffee'),
    ('Fuori Casa', 'Ristorante / Uscita', 'burger'),
    ('Fuori Casa', 'Delivery', 'pizza'),

    ('Veicoli & Trasporti', 'Carburante', 'fuel'),
    ('Veicoli & Trasporti', 'Assicurazione', 'shield'),
    ('Veicoli & Trasporti', 'Manutenzione', 'wrench'),
    ('Veicoli & Trasporti', 'Bollo', 'mail'),
    ('Veicoli & Trasporti', 'Multa', 'payments'),
    ('Veicoli & Trasporti', 'Rata / Finanziamento', 'loan'),
    ('Veicoli & Trasporti', 'Mezzi Pubblici / Taxi', 'metro'),

    ('Salute', 'Medico / Farmaci', 'pill'),
    ('Salute', 'Dentista / Specialisti', 'doctor'),

    ('Self Care', 'Parrucchiere / Estetista', 'spa'),
    ('Self Care', 'Cura Personale', 'beauty'),

    ('Shopping', 'Abbigliamento', 'clothes'),
    ('Shopping', 'Tecnologia', 'laptop'),
    ('Shopping', 'Regalo (fatto)', 'gift'),
    ('Shopping', 'Acquisti Extra / Altro', 'box'),

    ('Tempo Libero', 'Svago (cinema, eventi)', 'movie'),
    ('Tempo Libero', 'Hobby', 'camera'),
    ('Tempo Libero', 'Abbonamenti', 'subscription'),
    ('Tempo Libero', 'Sport / Palestra', 'golf'),

    ('Viaggio', 'Voli / Hotel', 'plane'),
    ('Viaggio', 'Trasporti di Viaggio', 'luggage'),

    // --- Entrate ---
    ('Stipendio', 'Stipendio', 'card'),
    ('Stipendio', 'Stipendio Extra', 'card'),
    ('Stipendio', 'Guadagno Extra', 'card'),

    ('Regalo', 'Regalo (ricevuto)', 'gift'),
  ];

  await db.transaction(() async {
    for (final (categoryName, name, icon) in subCategories) {
      await db.into(db.subCategories).insert(
            SubCategoriesCompanion.insert(
              categoryId: categoryIdByName(categoryName),
              name: name,
              icon: Value(icon),
              updatedAt: Value(kDefaultSeedUpdatedAt),
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
