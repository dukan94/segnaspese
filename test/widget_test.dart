// Test smoke minimale. Il template di default generato da
// `flutter create` referenziava un widget "MyApp" (contatore) che non
// esiste in questo progetto (l'app radice è `FinanceApp`, v. lib/app.dart).
//
// Un vero widget test su FinanceApp richiederebbe di inizializzare il
// database Drift/sqlite3 nativo nell'ambiente di test: lo affrontiamo con i
// test veri e propri pianificati per la Milestone M8 (test unitari su
// UseCase/repository, test widget sulle schermate chiave).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test ambiente di test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('ok'))),
    );

    expect(find.text('ok'), findsOneWidget);
  });
}
