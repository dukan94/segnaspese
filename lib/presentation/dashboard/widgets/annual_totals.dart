import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

/// Riga in cima alla Dashboard con i tre totali annui: entrate (verde),
/// uscite (rosso) e budget (colorato in base allo sforamento).
class AnnualTotals extends StatelessWidget {
  const AnnualTotals({
    super.key,
    required this.income,
    required this.expense,
    required this.budget,
    required this.isOverBudget,
  });

  final double income;
  final double expense;
  final double budget;
  final bool isOverBudget;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final green = Colors.green.shade600;
    final budgetColor = budget <= 0
        ? colorScheme.outline
        : (isOverBudget ? colorScheme.error : green);

    return Row(
      children: [
        Expanded(
          child: _StatCard(label: 'Entrate', amount: income, color: green),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
              label: 'Uscite', amount: expense, color: colorScheme.error),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Budget',
            amount: budget,
            color: budgetColor,
            subtitle: budget <= 0
                ? 'non impostato'
                : (isOverBudget ? 'sforato' : 'nei limiti'),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.amount,
    required this.color,
    this.subtitle,
  });

  final String label;
  final double amount;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                AppFormatters.currency(amount),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
