import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Riga in cima alla Dashboard con i tre totali: entrate (verde), uscite
/// (rosso) e budget (colorato in base allo sforamento). Ogni card ha una riga
/// di informazione secondaria, così hanno tutte la stessa altezza:
/// - Entrate → risparmio netto (entrate − uscite);
/// - Uscite → quota rispetto alle entrate;
/// - Budget → stato (non impostato / nei limiti / sforato).
class AnnualTotals extends StatelessWidget {
  const AnnualTotals({
    super.key,
    required this.income,
    required this.expense,
    required this.budget,
    required this.isOverBudget,
    required this.savings,
  });

  final double income;
  final double expense;
  final double budget;
  final bool isOverBudget;

  /// Risparmio netto del periodo (entrate − uscite).
  final double savings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final green = Colors.green.shade600;
    final budgetColor = budget <= 0
        ? colorScheme.outline
        : (isOverBudget ? colorScheme.error : green);
    final expensePct = income > 0 ? (expense / income * 100).round() : null;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Entrate',
            amount: income,
            color: green,
            subtitle: 'risparmio ${AppFormatters.signedCurrency(savings)}',
            subtitleColor: savings >= 0 ? green : colorScheme.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Uscite',
            amount: expense,
            color: colorScheme.error,
            subtitle:
                expensePct != null ? '$expensePct% delle entrate' : 'nessuna entrata',
          ),
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
    this.subtitleColor,
  });

  final String label;
  final double amount;
  final Color color;
  final String? subtitle;

  /// Colore del sottotitolo; se assente usa [color].
  final Color? subtitleColor;

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
                style: AppTheme.amountStyle(theme.textTheme.titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              // Su una sola riga, scalato per stare nella card: così tutte e
              // tre le card hanno la stessa altezza.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: subtitleColor ?? color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
