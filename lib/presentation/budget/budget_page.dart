import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../shared_widgets/content_width_limiter.dart';
import 'budget_providers.dart';
import 'widgets/add_icon.dart';
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
    final overviewAsync = ref.watch(
      yearOverviewProvider((year: _year, includeExtra: _includeExtraordinary)),
    );
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
                final tiles = [
                  for (final m in months)
                    _MonthTile(
                      overview: m,
                      isCurrent: _year == now.year && m.month == now.month,
                      isPast: m.year < now.year ||
                          (m.year == now.year && m.month < now.month),
                      onTap: () => _openMonth(m.year, m.month),
                    ),
                ];
                return ContentWidthLimiter(
                  // Più larga del default (640): qui dentro c'è la griglia
                  // dei 12 mesi su finestra larga (M29), non una colonna sola.
                  maxWidth: 960,
                  child: ListView(
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
                          onOpen: () =>
                              _openMonth(currentMonth.year, currentMonth.month),
                        ),
                      _MonthGrid(tiles: tiles),
                    ],
                  ),
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

/// 12 mesi comparabili e ripetuti → griglia 4 colonne su finestra larga
/// invece di una lista verticale che costringe a scorrere per vedere tutto
/// l'anno (M29, mockup discusso e approvato con Mario il 16 ago 2026).
/// Sotto la soglia, colonna singola come oggi. Altezza fissa per riga in
/// griglia: stesso contenuto di [_MonthTile], solo più compatto e allineato
/// in alto invece che occupare l'altezza naturale (variabile a seconda che
/// il mese abbia o no un budget impostato).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.tiles});

  final List<_MonthTile> tiles;

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
        mainAxisExtent: 144,
      ),
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

/// Intestazione della tile in modalità griglia (M29, fix 16 ago 2026): nome
/// mese e importi impilati su righe separate invece che affiancati — stesso
/// principio di `_GridHeader` in `budget_month_page.dart`.
class _GridMonthHeader extends StatelessWidget {
  const _GridMonthHeader({required this.overview, required this.isPast});

  final MonthBudgetOverview overview;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = AppFormatters.monthName(overview.year, overview.month);
    final capitalized = monthLabel[0].toUpperCase() + monthLabel.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                capitalized,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!overview.hasTotal && !isPast) const AddIcon(),
          ],
        ),
        const SizedBox(height: 3),
        if (overview.hasTotal)
          Text(
            '${AppFormatters.currency(overview.spent)} / ${AppFormatters.currency(overview.total!)}',
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else if (isPast)
          Text(
            'Nessun budget',
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

/// "Restano/Sforato" e "Da suddividere" impilati invece che affiancati con
/// uno `Spacer` — stesso motivo di [_GridMonthHeader].
class _GridRemainingStatus extends StatelessWidget {
  const _GridRemainingStatus({required this.overview});

  final MonthBudgetOverview overview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overview.isOverBudget)
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: colorScheme.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Sforato di ${AppFormatters.currency(-overview.remaining)}',
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else
          Text(
            'Restano ${AppFormatters.currency(overview.remaining)}',
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (!overview.hasCategoryBudgets)
          Text(
            'Da suddividere',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
              fontSize: 11.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.overview,
    required this.isCurrent,
    required this.isPast,
    required this.onTap,
  });

  final MonthBudgetOverview overview;
  final bool isCurrent;

  /// Mese già passato: non ha senso impostarci un budget. Resta consultabile
  /// (tap per vedere lo speso), ma viene mostrato in modo attenuato e senza
  /// l'invito "Imposta".
  final bool isPast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final barColor = overview.isOverBudget ? colorScheme.error : colorScheme.primary;
    final monthLabel = AppFormatters.monthName(overview.year, overview.month);

    final card = Card(
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
              if (isWideWindow(context))
                // Griglia (M29, fix 16 ago 2026): nome mese e importi
                // impilati invece che affiancati — stesso motivo di
                // _GridHeader in budget_month_page.dart (colonna di griglia
                // troppo stretta per entrambi sulla stessa riga senza
                // sovrapporsi).
                _GridMonthHeader(overview: overview, isPast: isPast)
              else
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
                    else if (isPast)
                      // Mese passato senza budget: niente invito "Imposta".
                      Text(
                        'Nessun budget',
                        style: TextStyle(color: colorScheme.outline),
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
                if (isWideWindow(context))
                  // Impilate, non affiancate con uno Spacer: in una colonna
                  // di griglia stretta non c'è spazio per "Restano/Sforato"
                  // e "Da suddividere" sulla stessa riga senza sovrapporsi.
                  _GridRemainingStatus(overview: overview)
                else
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

    // Mese passato: attenua l'intera card (resta comunque toccabile per la
    // consultazione).
    return isPast ? Opacity(opacity: 0.55, child: card) : card;
  }
}
