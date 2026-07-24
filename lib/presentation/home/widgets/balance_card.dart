import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

/// Card che mostra il saldo reale (somma di tutte le transazioni da sempre).
///
/// Il "Saldo Budget" del wireframe originale arriva con il modulo Budget
/// (Milestone M2): per ora la Home mostra solo il saldo reale.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = balance >= 0;
    final color = isPositive
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo reale', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              AppFormatters.signedCurrency(balance),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
