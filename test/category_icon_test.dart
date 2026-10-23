import 'package:finance_app/presentation/shared_widgets/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveCategoryIcon (M60)', () {
    test('chiave nota → icona corrispondente', () {
      expect(resolveCategoryIcon('home'), Icons.home_outlined);
      expect(resolveCategoryIcon(' cart '), Icons.shopping_cart_outlined);
    });

    test('emoji precedente a M60 → icona equivalente', () {
      expect(resolveCategoryIcon('🏠'), Icons.home_outlined);
      expect(resolveCategoryIcon('🛒'), Icons.shopping_cart_outlined);
    });

    test('emoji con selettore di variante o tono pelle riconosciuta', () {
      // Stesse forme salvate sul database reale (es. "🛍️", "👨🏻‍⚕️").
      expect(resolveCategoryIcon('🛍️'), Icons.shopping_bag_outlined);
      expect(resolveCategoryIcon('🛍'), Icons.shopping_bag_outlined);
      expect(resolveCategoryIcon('👨🏻‍⚕️'), Icons.medical_services_outlined);
    });

    test('vuoto o sconosciuto → ripiego', () {
      expect(resolveCategoryIcon(''), categoryFallbackIcon);
      expect(resolveCategoryIcon('🦄'), categoryFallbackIcon);
      expect(resolveCategoryIcon('chiave-inesistente'), categoryFallbackIcon);
      expect(resolveCategoryIcon('', fallback: Icons.euro), Icons.euro);
    });
  });

  group('subCategoryIconOr', () {
    test('sottocategoria con icona propria la tiene', () {
      expect(subCategoryIconOr('pizza', 'burger'), 'pizza');
      expect(subCategoryIconOr('🍕', 'burger'), '🍕');
    });

    test('sottocategoria senza icona riconosciuta usa quella del padre', () {
      expect(subCategoryIconOr('', 'burger'), 'burger');
      expect(subCategoryIconOr('🦄', 'burger'), 'burger');
    });
  });

  test('ogni chiave del selettore esiste nel catalogo, una sola volta', () {
    final keys = [for (final g in categoryIconGroups) ...g.keys];
    expect(keys.toSet().length, keys.length);
    expect(keys.toSet(), categoryIcons.keys.toSet());
  });
}
