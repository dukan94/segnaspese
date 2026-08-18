import 'package:finance_app/domain/services/money_rounding.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `roundToCents` (M42): helper unico per l'arrotondamento a 2
/// decimali, prima duplicato identico in 3 punti diversi del codice.
void main() {
  test('corregge il rumore di rappresentazione binaria (40.799999999999997 -> 40.8)', () {
    expect(roundToCents(40.799999999999997), 40.8);
  });

  test('arrotonda una divisione non esatta (50 / 3)', () {
    expect(roundToCents(50 / 3), 16.67);
  });

  test('non altera un valore già a 2 decimali', () {
    expect(roundToCents(19.99), 19.99);
  });

  test('funziona anche con valori negativi', () {
    expect(roundToCents(-40.799999999999997), -40.8);
  });
}
