import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../dashboard_providers.dart';
import 'count_badge.dart';

/// Barre orizzontali "classiche" della ripartizione per sottocategoria della
/// categoria selezionata nella torta.
///
/// Doppio click su una riga (M34): apre lo Storico con la ricerca testuale
/// già impostata sul nome della sottocategoria.
class SubcategoryBars extends StatelessWidget {
  const SubcategoryBars({
    super.key,
    required this.categoryName,
    required this.color,
    required this.slices,
    required this.amount,
    required this.budget,
    required this.onOpenHistory,
  });

  final String categoryName;
  final int color;
  final List<SubcategorySlice> slices;

  /// Speso e budget assegnato alla categoria nel periodo selezionato (M55),
  /// mostrati accanto al titolo — stesso formato "speso / tetto" della card
  /// "Budget" generale in cima alla Dashboard (M44).
  final double amount;
  final double budget;
  final ValueChanged<String> onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text('Dettaglio · $categoryName',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall),
        ),
        const SizedBox(width: 8),
        _CategoryBudgetSummary(amount: amount, budget: budget),
      ],
    );

    if (slices.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nessuna spesa per "$categoryName" nel periodo.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      );
    }

    final max = slices.first.amount; // già ordinate decrescenti dal provider
    final barColor = Color(color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        for (final slice in slices)
          InkWell(
            onDoubleTap: () => onOpenHistory(slice.name),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (slice.icon.isNotEmpty) ...[
                        Text(slice.icon, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(slice.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium),
                      ),
                      const SizedBox(width: 8),
                      Text(AppFormatters.currencyRounded(slice.amount),
                          style: AppTheme.amountStyle(theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Container(
                          height: 10,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        FractionallySizedBox(
                          widthFactor: max <= 0
                              ? 0
                              : (slice.amount / max).clamp(0.0, 1.0),
                          child: Container(height: 10, color: barColor),
                        ),
                      ],
                    ),
                  ),
                  if (slice.count > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CountBadge(count: slice.count),
                        const SizedBox(width: 6),
                        Text(
                          'media ${AppFormatters.currencyRounded(slice.average)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Speso / budget" della categoria selezionata, accanto al titolo del
/// pannello (M55) — stesso formato e stessa logica colore della card
/// "Budget" generale in cima alla Dashboard (`AnnualTotals`/`_StatCard`,
/// M44): nessun budget impostato → solo lo speso, senza "/"; altrimenti
/// verde se nei limiti, rosso se sforato.
class _CategoryBudgetSummary extends StatelessWidget {
  const _CategoryBudgetSummary({required this.amount, required this.budget});

  final double amount;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOverBudget = budget > 0 && amount > budget;
    final color = budget <= 0
        ? colorScheme.outline
        : (isOverBudget ? colorScheme.error : Colors.green.shade600);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          AppFormatters.currencyRounded(amount),
          style: AppTheme.amountStyle(theme.textTheme.bodyMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ),
        if (budget > 0)
          Text(
            ' / ${AppFormatters.currencyRounded(budget)}',
            style: AppTheme.amountStyle(theme.textTheme.bodySmall
                ?.copyWith(color: color, fontWeight: FontWeight.w400)),
          ),
      ],
    );
  }
}
