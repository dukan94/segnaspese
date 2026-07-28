import 'package:finance_app/presentation/shared_widgets/fade_in_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('il figlio parte trasparente e arriva a piena opacità', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FadeInItem(child: Text('riga')),
        ),
      ),
    );

    final finder = find.descendant(
      of: find.byType(FadeInItem),
      matching: find.byType(FadeTransition),
    );
    FadeTransition fadeTransitionOf(WidgetTester t) => t.widget<FadeTransition>(finder);

    // Subito dopo il primo pump l'animazione è appena partita.
    expect(fadeTransitionOf(tester).opacity.value, lessThan(0.5));

    await tester.pump(const Duration(milliseconds: 260));
    expect(fadeTransitionOf(tester).opacity.value, 1.0);
  });
}
