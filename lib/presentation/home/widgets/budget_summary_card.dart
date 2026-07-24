import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../budget/budget_providers.dart';

/// Card "Saldo Budget" + "% budget utilizzato" della Home (Milestone M2).
///
/// Usa il budget effettivo del mese corrente (totale mensile se impostato,
/// altrimenti somma delle allocazioni per categoria). Se non esiste alcun
/// budget invita a impostarne uno.
class BudgetSummaryCard extends StatelessWidget {
  const BudgetSummaryCard({super.key, required this.summary});

  final HomeBudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!summary.hasBudget) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.savings_outlined, color: colorScheme.primary),
          title: const Text('Nessun budget per questo mese'),
          subtitle: const Text('Imposta quanto vuoi spendere'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/budget'),
        ),
      );
    }

    final over = summary.isOverBudget;
    final barColor = over ? colorScheme.error : colorScheme.primary;
    final pctLabel = '${(summary.usedPct * 100).round()}%';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Saldo Budget', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  'Budget utilizzato: $pctLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppFormatters.signedCurrency(summary.remaining),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: over ? colorScheme.error : null,
                  ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: summary.usedPct.clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: barColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (over) ...[
                  Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                  const SizedBox(width: 4),
                  Text(
                    'Budget superato di ${AppFormatters.currency(-summary.remaining)}',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ] else
                  Text(
                    'Speso ${AppFormatters.currency(summary.spent)} di ${AppFormatters.currency(summary.budget!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
