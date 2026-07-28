import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../shared_widgets/animated_amount_text.dart';

/// Card che mostra il saldo del mese corrente (in evidenza) e, con meno
/// enfasi, il saldo dell'anno corrente da inizio anno a oggi.
///
/// Il "Saldo Budget" del wireframe originale arriva con il modulo Budget
/// (Milestone M2, v. [BudgetSummaryCard]): questa card è il saldo "reale"
/// (entrate meno uscite effettive), non quello pianificato.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.monthlyBalance,
    required this.yearlyBalance,
  });

  final double monthlyBalance;
  final double yearlyBalance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthColor = monthlyBalance >= 0
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo mese', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            AnimatedAmountText(
              value: monthlyBalance,
              formatter: AppFormatters.signedCurrency,
              style:
                  AppTheme.amountStyle(theme.textTheme.headlineMedium?.copyWith(
                color: monthColor,
                fontWeight: FontWeight.bold,
              )),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Saldo anno ',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                AnimatedAmountText(
                  value: yearlyBalance,
                  formatter: AppFormatters.signedCurrency,
                  style:
                      AppTheme.amountStyle(theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
