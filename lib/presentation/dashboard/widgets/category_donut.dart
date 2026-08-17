import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../dashboard_providers.dart';
import 'count_badge.dart';

/// Torta (ciambella) delle spese per categoria, con legenda tappabile: al tap
/// su una fetta o su una voce di legenda si seleziona la categoria (per il
/// dettaglio sottocategorie sotto). Al centro il totale delle uscite.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.total,
    required this.selectedCategoryId,
    required this.onSelect,
  });

  final List<CategorySlice> slices;
  final double total;
  final int? selectedCategoryId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (slices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('Nessuna spesa nel periodo',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 56,
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.amount,
                        color: Color(slice.color),
                        radius:
                            slice.categoryId == selectedCategoryId ? 46 : 38,
                        showTitle: false,
                      ),
                  ],
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions) return;
                      final section = response?.touchedSection;
                      if (section == null) return;
                      final index = section.touchedSectionIndex;
                      if (index >= 0 && index < slices.length) {
                        onSelect(slices[index].categoryId);
                      }
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Uscite', style: theme.textTheme.labelSmall),
                  Text(
                    AppFormatters.currency(total),
                    style: AppTheme.amountStyle(theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final slice in slices)
          _LegendRow(
            slice: slice,
            total: total,
            selected: slice.categoryId == selectedCategoryId,
            onTap: () => onSelect(slice.categoryId),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final CategorySlice slice;
  final double total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0.0 : slice.amount / total * 100;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          // start, non center (default): con la seconda riga
          // badge/media sotto il nome, il pallino/pct/importo devono
          // restare allineati alla prima riga, non centrati sull'intero
          // blocco a due righe.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 5),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Color(slice.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            if (slice.icon.isNotEmpty) ...[
              Text(slice.icon, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slice.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  if (slice.count > 0) ...[
                    const SizedBox(height: 3),
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
            Text('${pct.toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(width: 10),
            Text(AppFormatters.currency(slice.amount),
                style: AppTheme.amountStyle(theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
