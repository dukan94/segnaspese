import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/budget_providers.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../shared_widgets/content_width_limiter.dart';
import 'budget_providers.dart';
import 'widgets/budget_amount_dialog.dart';

/// Dettaglio del budget di un mese: totale del mese e suddivisione tra le
/// categorie di uscita. Raggiungibile per qualsiasi mese (anche futuri), così
/// da poter pianificare in anticipo. Lo sforamento è sempre consentito e viene
/// solo segnalato (barre rosse, avvisi).
class BudgetMonthPage extends ConsumerWidget {
  const BudgetMonthPage({super.key, required this.year, required this.month});

  final int year;
  final int month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = MonthKey(year, month);
    final detailAsync = ref.watch(monthDetailProvider(key));
    final title = AppFormatters.monthYear(year, month);
    final now = DateTime.now();
    // Mese già passato: consultabile ma non impostabile (niente pulsanti di
    // modifica del budget).
    final readOnly =
        year < now.year || (year == now.year && month < now.month);

    return Scaffold(
      appBar: AppBar(
        title: Text(title[0].toUpperCase() + title.substring(1)),
      ),
      body: detailAsync.when(
        data: (detail) =>
            _MonthDetailBody(detail: detail, monthKey: key, readOnly: readOnly),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
      ),
    );
  }
}

class _MonthDetailBody extends StatelessWidget {
  const _MonthDetailBody({
    required this.detail,
    required this.monthKey,
    required this.readOnly,
  });

  final MonthBudgetDetail detail;
  final MonthKey monthKey;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final monthLabel = AppFormatters.monthName(detail.year, detail.month);
    final tiles = [
      for (final line in detail.lines)
        _CategoryBudgetTile(
          line: line,
          monthKey: monthKey,
          monthLabel: monthLabel,
          readOnly: readOnly,
        ),
    ];

    return ContentWidthLimiter(
      // Più larga del default (640): qui dentro c'è la griglia delle
      // categorie su finestra larga (M29), non una colonna sola.
      maxWidth: 960,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _TotalCard(
            detail: detail,
            monthKey: monthKey,
            monthLabel: monthLabel,
            readOnly: readOnly,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              'Suddivisione per categoria',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (detail.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessuna categoria di uscita. Aggiungine dalle Impostazioni.'),
            )
          else
            _CategoryGrid(tiles: tiles),
        ],
      ),
    );
  }
}

/// Stesso principio di `_MonthGrid` in `budget_page.dart`: categorie
/// comparabili e ripetute → griglia 4 colonne su finestra larga (M29),
/// colonna singola sotto la soglia.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.tiles});

  final List<_CategoryBudgetTile> tiles;

  @override
  Widget build(BuildContext context) {
    if (!isWideWindow(context)) {
      return Column(children: tiles);
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 128,
      ),
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.detail,
    required this.monthKey,
    required this.monthLabel,
    required this.readOnly,
  });

  final MonthBudgetDetail detail;
  final MonthKey monthKey;
  final String monthLabel;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget totale del mese',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        detail.hasTotal
                            ? AppFormatters.currency(detail.total!)
                            : 'Non impostato',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                if (!readOnly)
                  if (detail.hasTotal)
                    // Budget già impostato: la modifica è un'azione ormai
                    // familiare in questo contesto, basta l'icona.
                    IconButton(
                      onPressed: () => showBudgetAmountDialog(
                        context,
                        month: monthKey,
                        title: 'Budget totale — $monthLabel',
                        subtitle: 'Importo complessivo che vuoi spendere nel mese.',
                        initialAmount: detail.total,
                        existingId: detail.totalBudgetId,
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Modifica',
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: () => showBudgetAmountDialog(
                        context,
                        month: monthKey,
                        title: 'Budget totale — $monthLabel',
                        subtitle: 'Importo complessivo che vuoi spendere nel mese.',
                        initialAmount: detail.total,
                        existingId: detail.totalBudgetId,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Imposta'),
                    ),
              ],
            ),
            if (detail.hasTotal) ...[
              const Divider(height: 24),
              _AllocationSummary(detail: detail),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllocationSummary extends StatelessWidget {
  const _AllocationSummary({required this.detail});

  final MonthBudgetDetail detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unallocated = detail.unallocated ?? 0;
    final pct = detail.total == null || detail.total == 0
        ? 0.0
        : (detail.allocated / detail.total!).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Assegnato', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text(
              '${AppFormatters.currency(detail.allocated)} / ${AppFormatters.currency(detail.total!)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
            color: detail.isOverAllocated ? colorScheme.error : colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        if (detail.isOverAllocated)
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Hai assegnato ${AppFormatters.currency(-unallocated)} in più del totale.',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ],
          )
        else
          Text(
            'Da assegnare: ${AppFormatters.currency(unallocated)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _CategoryBudgetTile extends StatelessWidget {
  const _CategoryBudgetTile({
    required this.line,
    required this.monthKey,
    required this.monthLabel,
    required this.readOnly,
  });

  final CategoryBudgetLine line;
  final MonthKey monthKey;
  final String monthLabel;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = line.category;
    final barColor = line.isOverBudget ? colorScheme.error : Color(category.color);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: readOnly
            ? null
            : () => showBudgetAmountDialog(
                  context,
                  month: monthKey,
                  categoryId: category.id,
                  title: '${category.name} — $monthLabel',
                  subtitle: 'Quanto vuoi destinare a questa categoria nel mese.',
                  initialAmount: line.allocation,
                  existingId: line.budgetId,
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(category.color).withValues(alpha: 0.2),
                    child: Text(category.icon, style: const TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (line.hasAllocation)
                    Text(
                      '${AppFormatters.currency(line.spent)} / ${AppFormatters.currency(line.allocation!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else if (readOnly)
                    // Mese passato: niente invito ad aggiungere un budget.
                    Text('Nessun budget',
                        style: TextStyle(color: colorScheme.outline))
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Aggiungi', style: TextStyle(color: colorScheme.primary)),
                        Icon(Icons.add, color: colorScheme.primary, size: 18),
                      ],
                    ),
                ],
              ),
              if (line.hasAllocation) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: line.usedPct.clamp(0, 1).toDouble(),
                    minHeight: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: barColor,
                  ),
                ),
                const SizedBox(height: 5),
                if (line.isOverBudget)
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 15, color: colorScheme.error),
                      const SizedBox(width: 4),
                      Text(
                        'Sforato di ${AppFormatters.currency(-line.remaining)}',
                        style: TextStyle(color: colorScheme.error, fontSize: 12),
                      ),
                    ],
                  )
                else
                  Text(
                    'Restano ${AppFormatters.currency(line.remaining)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ] else if (line.spent > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Speso ${AppFormatters.currency(line.spent)} (nessun budget)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
