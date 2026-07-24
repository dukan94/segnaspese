import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import 'budget_providers.dart';
import 'widgets/annual_summary_card.dart';

/// Pagina Budget (Milestone M2).
///
/// Vista annuale: per ogni mese dell'anno si imposta un budget totale
/// (singolarmente, mese per mese). Toccando un mese si apre il dettaglio, dove
/// il totale viene suddiviso tra le categorie. Il mese corrente, se ha un
/// totale ma non è ancora ripartito, mostra un invito a suddividerlo.
class BudgetPage extends ConsumerStatefulWidget {
  const BudgetPage({super.key});

  @override
  ConsumerState<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends ConsumerState<BudgetPage> {
  late int _year = DateTime.now().year;
  bool _includeExtraordinary = false;

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(yearOverviewProvider(_year));
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      body: Column(
        children: [
          _YearSelector(
            year: _year,
            onPrev: () => setState(() => _year--),
            onNext: () => setState(() => _year++),
          ),
          Expanded(
            child: overviewAsync.when(
              data: (months) {
                final currentMonth = _year == now.year
                    ? months.firstWhere((m) => m.month == now.month)
                    : null;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  children: [
                    AnnualSummaryCard(
                      year: _year,
                      includeExtra: _includeExtraordinary,
                      onIncludeExtraChanged: (v) =>
                          setState(() => _includeExtraordinary = v),
                    ),
                    if (currentMonth != null)
                      _CurrentMonthPrompt(
                        overview: currentMonth,
                        onOpen: () => _openMonth(currentMonth.year, currentMonth.month),
                      ),
                    for (final m in months)
                      _MonthTile(
                        overview: m,
                        isCurrent: _year == now.year && m.month == now.month,
                        onTap: () => _openMonth(m.year, m.month),
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Errore: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _openMonth(int year, int month) {
    context.push('/budget/month/$year/$month');
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.year,
    required this.onPrev,
    required this.onNext,
  });

  final int year;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Anno precedente',
          ),
          Text(
            '$year',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Anno successivo',
          ),
        ],
      ),
    );
  }
}

/// Invito contestuale per il mese corrente: imposta il totale o suddividilo.
class _CurrentMonthPrompt extends StatelessWidget {
  const _CurrentMonthPrompt({required this.overview, required this.onOpen});

  final MonthBudgetOverview overview;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final String message;
    final String action;
    if (!overview.hasTotal) {
      message = 'Non hai ancora impostato il budget di questo mese.';
      action = 'Imposta';
    } else if (!overview.hasCategoryBudgets) {
      message =
          'Suddividi il budget di ${AppFormatters.monthName(overview.year, overview.month)} '
          'tra le categorie.';
      action = 'Suddividi';
    } else {
      return const SizedBox.shrink();
    }

    return Card(
      color: colorScheme.secondaryContainer,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.tips_and_updates_outlined, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onSecondaryContainer),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: onOpen, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.overview,
    required this.isCurrent,
    required this.onTap,
  });

  final MonthBudgetOverview overview;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final barColor = overview.isOverBudget ? colorScheme.error : colorScheme.primary;
    final monthLabel = AppFormatters.monthName(overview.year, overview.month);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      shape: isCurrent
          ? RoundedRectangleBorder(
              side: BorderSide(color: colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      monthLabel[0].toUpperCase() + monthLabel.substring(1),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (overview.hasTotal)
                    Text(
                      '${AppFormatters.currency(overview.spent)} / ${AppFormatters.currency(overview.total!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Imposta', style: TextStyle(color: colorScheme.primary)),
                        Icon(Icons.chevron_right, color: colorScheme.primary, size: 20),
                      ],
                    ),
                ],
              ),
              if (overview.hasTotal) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: overview.usedPct.clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: barColor,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (overview.isOverBudget) ...[
                      Icon(Icons.warning_amber_rounded, size: 16, color: colorScheme.error),
                      const SizedBox(width: 4),
                      Text(
                        'Sforato di ${AppFormatters.currency(-overview.remaining)}',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ] else
                      Text(
                        'Restano ${AppFormatters.currency(overview.remaining)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const Spacer(),
                    if (!overview.hasCategoryBudgets)
                      Text(
                        'Da suddividere',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
