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
    required this.onOpenHistory,
  });

  final String categoryName;
  final int color;
  final List<SubcategorySlice> slices;
  final ValueChanged<String> onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (slices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Nessuna spesa per "$categoryName" nel periodo.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }

    final max = slices.first.amount; // già ordinate decrescenti dal provider
    final barColor = Color(color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dettaglio · $categoryName', style: theme.textTheme.titleSmall),
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
                      Text(AppFormatters.currency(slice.amount),
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
                          'media ${AppFormatters.currency(slice.average)}',
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
