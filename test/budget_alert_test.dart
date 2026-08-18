import 'package:finance_app/presentation/budget/budget_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test di `shouldShowBudgetAlert` (M40): logica pura di quando mostrare
/// l'avviso soglia budget in Home, estratta apposta per essere testabile
/// senza Riverpod/Drift.
void main() {
  group('shouldShowBudgetAlert', () {
    test('nessun budget impostato: mai true, indipendentemente dallo speso',
        () {
      const summary = HomeBudgetSummary(budget: null, spent: 1000);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: null,
        ),
        isFalse,
      );
    });

    test('sotto soglia (90%): false', () {
      const summary = HomeBudgetSummary(budget: 1000, spent: 899);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: null,
        ),
        isFalse,
      );
    });

    test('esattamente alla soglia (90%): true', () {
      const summary = HomeBudgetSummary(budget: 1000, spent: 900);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: null,
        ),
        isTrue,
      );
    });

    test('sopra soglia ma non ancora chiuso questo mese: true', () {
      const summary = HomeBudgetSummary(budget: 1000, spent: 950);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: null,
        ),
        isTrue,
      );
    });

    test('già sforato (>100%): true, stesso banner della soglia', () {
      const summary = HomeBudgetSummary(budget: 1000, spent: 1200);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: null,
        ),
        isTrue,
      );
    });

    test('chiuso per il mese corrente: false', () {
      const summary = HomeBudgetSummary(budget: 1000, spent: 950);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: '2026-08',
        ),
        isFalse,
      );
    });

    test('chiuso per un mese diverso (es. il precedente): riappare, true',
        () {
      const summary = HomeBudgetSummary(budget: 1000, spent: 950);
      expect(
        shouldShowBudgetAlert(
          summary: summary,
          currentMonthKey: '2026-08',
          dismissedMonth: '2026-07',
        ),
        isTrue,
      );
    });
  });
}
