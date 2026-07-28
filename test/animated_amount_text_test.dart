import 'package:finance_app/presentation/shared_widgets/animated_amount_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(double value) => MaterialApp(
        home: Scaffold(
          body: AnimatedAmountText(
            value: value,
            formatter: (v) => v.toStringAsFixed(2),
            duration: const Duration(milliseconds: 500),
          ),
        ),
      );

  testWidgets('conta da 0 al valore al primo montaggio, non salta subito al valore finale',
      (tester) async {
    await tester.pumpWidget(wrap(100));

    // Al primo frame l'animazione è appena partita: non deve già mostrare il
    // valore finale (altrimenti "anima" solo sulla carta, non a schermo).
    expect(find.text('100.00'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    final midText = tester.widget<Text>(find.byType(Text)).data!;
    final midValue = double.parse(midText);
    expect(midValue, greaterThan(0), reason: 'deve essere avanzata oltre lo 0 iniziale');
    expect(midValue, lessThan(100), reason: 'non deve aver già raggiunto il valore finale a metà durata');

    await tester.pump(const Duration(milliseconds: 260));
    expect(find.text('100.00'), findsOneWidget);
  });

  testWidgets('quando il valore cambia riparte dal valore attuale mostrato, non da zero',
      (tester) async {
    await tester.pumpWidget(wrap(100));
    await tester.pumpAndSettle();
    expect(find.text('100.00'), findsOneWidget);

    await tester.pumpWidget(wrap(200));
    await tester.pump(const Duration(milliseconds: 10));
    final justAfterChange = double.parse(tester.widget<Text>(find.byType(Text)).data!);
    expect(justAfterChange, greaterThanOrEqualTo(99),
        reason: 'deve partire da vicino al valore precedente (100), non da 0');

    await tester.pumpAndSettle();
    expect(find.text('200.00'), findsOneWidget);
  });
}
