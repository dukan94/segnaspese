import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../budget/budget_providers.dart';
import '../../shared_widgets/animated_amount_text.dart';

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
      final warningFg = AppTheme.onWarningContainer(context);
      return Card(
        color: AppTheme.warningContainer(context),
        child: ListTile(
          leading: Icon(Icons.warning_amber_rounded, color: warningFg),
          title: Text('Nessun budget per questo mese',
              style: TextStyle(color: warningFg, fontWeight: FontWeight.w600)),
          subtitle: Text('Imposta quanto vuoi spendere',
              style: TextStyle(color: warningFg.withValues(alpha: 0.85))),
          trailing: Icon(Icons.chevron_right, color: warningFg),
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
                Text('Saldo Budget',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  'Budget utilizzato: $pctLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedAmountText(
              value: summary.remaining,
              formatter: AppFormatters.signedCurrency,
              style: AppTheme.amountStyle(
                  Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: over ? colorScheme.error : null,
                      )),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                    begin: 0, end: summary.usedPct.clamp(0, 1).toDouble()),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, animatedPct, child) =>
                    LinearProgressIndicator(
                  value: animatedPct,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: barColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (over) ...[
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: colorScheme.error),
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
