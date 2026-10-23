import 'package:flutter/material.dart';

/// Icone di categorie/sottocategorie (M60): icone Material vettoriali,
/// tinte col colore della categoria, al posto delle emoji (che hanno colori
/// propri e non si possono ricolorare).
///
/// Nel database (colonna `icon` di Categories/SubCategories) si salva la
/// CHIAVE testuale dell'icona (es. `"home"`), non `IconData`: nessuna
/// modifica di schema, e la sync Turso continua a trattarla come testo.
/// Le righe create prima di M60 contengono ancora un'emoji: non vengono
/// riscritte (v. regola M52 su `updatedAt`), ma [resolveCategoryIcon] le
/// traduce al volo tramite [_legacyEmojiToKey]. Una riga passa alla chiave
/// nuova quando la si modifica dal form.

/// Gruppo di icone mostrato nel selettore del form categoria.
class CategoryIconGroup {
  const CategoryIconGroup(this.label, this.keys);
  final String label;
  final List<String> keys;
}

/// Tutte le icone disponibili, per chiave. Le chiavi sono salvate nel
/// database e sincronizzate: **non rinominarne mai una** (le righe che la
/// usano finirebbero sull'icona di ripiego); aggiungerne è sempre sicuro.
const Map<String, IconData> categoryIcons = {
  // Casa
  'home': Icons.home_outlined,
  'sofa': Icons.chair_outlined,
  'receipt': Icons.receipt_long_outlined,
  'cleaning': Icons.cleaning_services_outlined,
  'bolt': Icons.bolt_outlined,
  'water': Icons.water_drop_outlined,
  'wifi': Icons.wifi,
  'phone': Icons.smartphone_outlined,
  'plug': Icons.power_outlined,
  'construction': Icons.construction_outlined,
  'pets': Icons.pets_outlined,
  'child': Icons.child_friendly_outlined,
  // Cibo
  'cart': Icons.shopping_cart_outlined,
  'basket': Icons.shopping_basket_outlined,
  'bakery': Icons.bakery_dining_outlined,
  'coffee': Icons.local_cafe_outlined,
  'restaurant': Icons.restaurant_outlined,
  'burger': Icons.lunch_dining_outlined,
  'pizza': Icons.local_pizza_outlined,
  'icecream': Icons.icecream_outlined,
  'bar': Icons.local_bar_outlined,
  'delivery': Icons.delivery_dining_outlined,
  // Trasporti
  'car': Icons.directions_car_outlined,
  'motorbike': Icons.two_wheeler_outlined,
  'bike': Icons.pedal_bike_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'wrench': Icons.build_outlined,
  'parking': Icons.local_parking_outlined,
  'bus': Icons.directions_bus_outlined,
  'metro': Icons.subway_outlined,
  'train': Icons.train_outlined,
  'taxi': Icons.local_taxi_outlined,
  'shield': Icons.shield_outlined,
  'gavel': Icons.gavel_outlined,
  // Salute e cura
  'health': Icons.health_and_safety_outlined,
  'pill': Icons.medication_outlined,
  'doctor': Icons.medical_services_outlined,
  'hospital': Icons.local_hospital_outlined,
  'glasses': Icons.visibility_outlined,
  'spa': Icons.spa_outlined,
  'beauty': Icons.face_retouching_natural_outlined,
  'gym': Icons.fitness_center_outlined,
  // Shopping
  'bag': Icons.shopping_bag_outlined,
  'clothes': Icons.checkroom_outlined,
  'laptop': Icons.laptop_outlined,
  'gift': Icons.card_giftcard_outlined,
  'box': Icons.inventory_2_outlined,
  'flower': Icons.local_florist_outlined,
  'book': Icons.menu_book_outlined,
  // Tempo libero
  'ski': Icons.downhill_skiing_outlined,
  'golf': Icons.sports_golf_outlined,
  'soccer': Icons.sports_soccer_outlined,
  'movie': Icons.movie_outlined,
  'theater': Icons.theater_comedy_outlined,
  'music': Icons.music_note_outlined,
  'game': Icons.sports_esports_outlined,
  'camera': Icons.photo_camera_outlined,
  'subscription': Icons.subscriptions_outlined,
  'celebration': Icons.celebration_outlined,
  // Viaggio
  'plane': Icons.flight_outlined,
  'hotel': Icons.hotel_outlined,
  'luggage': Icons.luggage_outlined,
  'beach': Icons.beach_access_outlined,
  'map': Icons.map_outlined,
  // Denaro
  'euro': Icons.euro,
  'card': Icons.credit_card_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'bank': Icons.account_balance_outlined,
  'piggy': Icons.savings_outlined,
  'payments': Icons.payments_outlined,
  'loan': Icons.request_quote_outlined,
  'refund': Icons.undo,
  'trending': Icons.trending_up,
  'work': Icons.work_outline,
  'school': Icons.school_outlined,
  'eco': Icons.eco_outlined,
  'mail': Icons.mail_outline,
  'heart': Icons.volunteer_activism_outlined,
  'category': Icons.category_outlined,
};

/// Ordine e raggruppamento del selettore icone (stesse chiavi di
/// [categoryIcons], ognuna una sola volta).
const List<CategoryIconGroup> categoryIconGroups = [
  CategoryIconGroup('Casa', [
    'home', 'sofa', 'receipt', 'cleaning', 'bolt', 'water', 'wifi',
    'phone', 'plug', 'construction', 'pets', 'child',
  ]),
  CategoryIconGroup('Cibo', [
    'cart', 'basket', 'bakery', 'coffee', 'restaurant', 'burger',
    'pizza', 'icecream', 'bar', 'delivery',
  ]),
  CategoryIconGroup('Trasporti', [
    'car', 'motorbike', 'bike', 'fuel', 'wrench', 'parking', 'bus',
    'metro', 'train', 'taxi', 'shield', 'gavel',
  ]),
  CategoryIconGroup('Salute e cura', [
    'health', 'pill', 'doctor', 'hospital', 'glasses', 'spa', 'beauty',
    'gym',
  ]),
  CategoryIconGroup('Shopping', [
    'bag', 'clothes', 'laptop', 'gift', 'box', 'flower', 'book',
  ]),
  CategoryIconGroup('Tempo libero', [
    'ski', 'golf', 'soccer', 'movie', 'theater', 'music', 'game',
    'camera', 'subscription', 'celebration',
  ]),
  CategoryIconGroup('Viaggio', [
    'plane', 'hotel', 'luggage', 'beach', 'map',
  ]),
  CategoryIconGroup('Denaro e altro', [
    'euro', 'card', 'wallet', 'bank', 'piggy', 'payments', 'loan',
    'refund', 'trending', 'work', 'school', 'eco', 'mail', 'heart',
    'category',
  ]),
];

/// Emoji usate prima di M60 (seed + quelle scelte a mano sul database
/// reale di Mario, 23 ott 2026) → chiave equivalente. Confronto fatto dopo
/// [_normalizeEmoji], quindi qui senza selettori di variante/tono pelle.
const Map<String, String> _legacyEmojiToKey = {
  '🏠': 'home',
  '🛋': 'sofa',
  '🧾': 'receipt',
  '🧹': 'cleaning',
  '💶': 'euro',
  '🛒': 'cart',
  '🥖': 'bakery',
  '🥐': 'coffee',
  '🍔': 'burger',
  '🍕': 'pizza',
  '🚗': 'car',
  '⛽': 'fuel',
  '🛡': 'shield',
  '🧼': 'wrench',
  '✉': 'mail',
  '💸': 'payments',
  '🧧': 'loan',
  '🚇': 'metro',
  '💊': 'pill',
  '🍏': 'health',
  '🦷': 'doctor',
  '👨⚕': 'doctor',
  '💆': 'spa',
  '💅': 'beauty',
  '🛍': 'bag',
  '👗': 'clothes',
  '💻': 'laptop',
  '🎁': 'gift',
  '📦': 'box',
  '🔌': 'plug',
  '⛷': 'ski',
  '🎬': 'movie',
  '📸': 'camera',
  '🖊': 'subscription',
  '🏌': 'golf',
  '✈': 'plane',
  '🛫': 'plane',
  '🧳': 'luggage',
  '🛖': 'hotel',
  '🍨': 'icecream',
  '🎭': 'theater',
  '🚄': 'train',
  '💳': 'card',
  '🔙': 'refund',
  '🌱': 'eco',
  '🏤': 'bank',
  '🐖': 'piggy',
};

/// Toglie selettore di variante (U+FE0F), ZWJ (U+200D) e modificatori di
/// tono pelle (U+1F3FB–1F3FF): la stessa emoji può arrivare con o senza.
String _normalizeEmoji(String s) => String.fromCharCodes(s.runes.where((r) =>
    r != 0xFE0F && r != 0x200D && (r < 0x1F3FB || r > 0x1F3FF)));

/// Icona di ripiego per una categoria senza icona riconosciuta.
const IconData categoryFallbackIcon = Icons.category_outlined;

/// Chiave dell'icona per il valore salvato [stored] (chiave M60 o emoji
/// precedente), o `null` se vuoto/non riconosciuto.
String? categoryIconKeyFor(String stored) {
  final trimmed = stored.trim();
  if (trimmed.isEmpty) return null;
  if (categoryIcons.containsKey(trimmed)) return trimmed;
  return _legacyEmojiToKey[_normalizeEmoji(trimmed)];
}

/// Icona da mostrare per una sottocategoria: la sua, o quella della
/// categoria padre se non ne ha una riconosciuta (l'icona è opzionale).
String subCategoryIconOr(String subCategoryIcon, String categoryIcon) =>
    categoryIconKeyFor(subCategoryIcon) != null ? subCategoryIcon : categoryIcon;

/// `IconData` per il valore salvato [stored], o [fallback] se vuoto/non
/// riconosciuto.
IconData resolveCategoryIcon(
  String stored, {
  IconData fallback = categoryFallbackIcon,
}) {
  final key = categoryIconKeyFor(stored);
  return key == null ? fallback : categoryIcons[key]!;
}

/// Colore dell'icona su tema scuro: il colore pieno della categoria (spesso
/// scuro, es. verde bosco) sparirebbe sullo sfondo, quindi lo si schiarisce.
Color categoryIconForeground(BuildContext context, int color) {
  final base = Color(color);
  return Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(base, Colors.white, 0.4)!
      : base;
}

/// Icona categoria (scelta di Mario, M60): icona nel colore della categoria
/// su cerchio dello stesso colore molto tenue. Con `circle: false` solo
/// l'icona colorata, per i punti dove sta in linea col testo.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.icon,
    required this.color,
    this.radius = 18,
    this.circle = true,
    this.fallback = categoryFallbackIcon,
  });

  /// Valore salvato nella colonna `icon` (chiave o emoji precedente).
  final String icon;

  /// Colore ARGB della categoria (per una sottocategoria: della categoria
  /// padre).
  final int color;

  /// Raggio del cerchio; senza cerchio, metà della dimensione dell'icona.
  final double radius;
  final bool circle;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      resolveCategoryIcon(icon, fallback: fallback),
      size: circle ? radius * 1.1 : radius * 2,
      color: categoryIconForeground(context, color),
    );
    if (!circle) return glyph;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(color).withValues(alpha: 0.15),
      child: glyph,
    );
  }
}
