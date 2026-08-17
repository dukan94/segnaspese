import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../shared_widgets/content_width_limiter.dart';
import 'dashboard_providers.dart';
import 'widgets/annual_totals.dart';
import 'widgets/category_donut.dart';
import 'widgets/monthly_trend_chart.dart';
import 'widgets/subcategory_bars.dart';

/// Dashboard e statistiche (Milestone M4, fase A).
///
/// Vista annuale: totali entrate/uscite/budget, torta delle spese per
/// categoria con dettaglio a barre della sottocategoria selezionata, e
/// andamento mensile delle uscite con il budget come linea tratteggiata.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  late int _year = DateTime.now().year;
  int? _month; // null = intero anno; valorizzato = mese specifico
  int? _selectedCategoryId;
  bool _includeExtraordinary = false;

  void _goPrev() {
    if (_month == null) {
      _year--;
    } else if (_month == 1) {
      _month = 12;
      _year--;
    } else {
      _month = _month! - 1;
    }
  }

  void _goNext() {
    if (_month == null) {
      _year++;
    } else if (_month == 12) {
      _month = 1;
      _year++;
    } else {
      _month = _month! + 1;
    }
  }

  /// Doppio click su una categoria/sottocategoria (M34): apre lo Storico con
  /// la ricerca testuale già impostata sul nome cliccato.
  void _openHistory(BuildContext context, String name) {
    context.push('/history', extra: name);
  }

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(
      dashboardDataProvider(
        (year: _year, month: _month, includeExtra: _includeExtraordinary),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: dataAsync.when(
        data: (data) => _body(context, data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
      ),
    );
  }

  Widget _body(BuildContext context, DashboardData data) {
    // Categoria selezionata per il dettaglio: quella scelta se ancora valida,
    // altrimenti la prima (spesa più alta).
    final available = data.byCategory.map((c) => c.categoryId).toSet();
    final selectedId =
        (_selectedCategoryId != null && available.contains(_selectedCategoryId))
            ? _selectedCategoryId!
            : (data.byCategory.isNotEmpty
                ? data.byCategory.first.categoryId
                : null);

    final selectedSlice = selectedId == null
        ? null
        : data.byCategory.firstWhere((c) => c.categoryId == selectedId);

    final donutCard = _SectionCard(
      title: 'Spese per categoria',
      child: CategoryDonut(
        slices: data.byCategory,
        total: data.totalExpense,
        selectedCategoryId: selectedId,
        onSelect: (id) => setState(() => _selectedCategoryId = id),
        onOpenHistory: (name) => _openHistory(context, name),
      ),
    );

    final subcategoryCard = selectedSlice == null
        ? null
        : _SectionCard(
            child: SubcategoryBars(
              categoryName: selectedSlice.name,
              color: selectedSlice.color,
              slices: data.subByCategory[selectedId] ?? const [],
              onOpenHistory: (name) => _openHistory(context, name),
            ),
          );

    // L'andamento è una vista annuale: ha senso solo in modalità "Anno".
    // Segue la stessa categoria selezionata nella torta (come il dettaglio
    // sottocategorie sopra), non il totale: quando cambi fetta selezionata
    // cambia anche questo grafico.
    final trendCard = _month != null
        ? null
        : _SectionCard(
            title: selectedSlice == null
                ? 'Andamento 12 mesi'
                : 'Andamento 12 mesi · ${selectedSlice.name}',
            child: MonthlyTrendChart(
              monthlyExpense: selectedId == null
                  ? data.monthlyExpense
                  : (data.monthlyExpenseByCategory[selectedId] ??
                      List.filled(12, 0)),
              monthlyBudget: selectedId == null
                  ? data.monthlyBudget
                  : (data.monthlyBudgetByCategory[selectedId] ??
                      List.filled(12, 0)),
            ),
          );

    return ContentWidthLimiter(
      // Più larga del default (640): qui dentro ci sono due colonne di
      // grafici affiancate su finestra larga (M28), non una colonna sola.
      maxWidth: 960,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _PeriodSelector(
            year: _year,
            month: _month,
            onModeChanged: (monthMode) => setState(() {
              if (monthMode) {
                // Passa a "Mese": default al mese corrente se siamo
                // nell'anno corrente, altrimenti dicembre.
                final now = DateTime.now();
                _month = (_year == now.year) ? now.month : 12;
              } else {
                _month = null;
              }
            }),
            onPrev: () => setState(_goPrev),
            onNext: () => setState(_goNext),
          ),
          const SizedBox(height: 8),
          AnnualTotals(
            income: data.totalIncome,
            expense: data.totalExpense,
            budget: data.totalBudget,
            isOverBudget: data.isOverBudget,
            savings: data.savings,
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _includeExtraordinary,
            onChanged: (v) => setState(() => _includeExtraordinary = v),
            title: const Text('Includi operazioni straordinarie'),
            dense: true,
          ),
          const SizedBox(height: 8),
          _ChartsSection(
            donut: donutCard,
            subcategory: subcategoryCard,
            trend: trendCard,
          ),
        ],
      ),
    );
  }
}

/// Colonna sinistra: solo la torta "Spese per categoria" (con la sua
/// legenda). Colonna destra: andamento 12 mesi sopra, barre sottocategoria
/// sotto — riordinato su richiesta di Mario (17 ago 2026, prima la
/// sottocategoria stava affiancata alla torta a sinistra, sotto l'andamento
/// annuale a destra). Solo su finestra larga; sotto la soglia, tutto
/// impilato come oggi (torta, sottocategoria, andamento).
class _ChartsSection extends StatelessWidget {
  const _ChartsSection({
    required this.donut,
    required this.subcategory,
    required this.trend,
  });

  final Widget donut;
  final Widget? subcategory;
  final Widget? trend;

  @override
  Widget build(BuildContext context) {
    if (!isWideWindow(context)) {
      return Column(
        children: [
          donut,
          if (subcategory != null) subcategory!,
          if (trend != null) trend!,
        ],
      );
    }
    if (trend == null && subcategory == null) {
      // Nessuna categoria selezionata e vista "Mese" (niente andamento):
      // niente da affiancare alla torta, resta da sola.
      return donut;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 85, child: donut),
        const SizedBox(width: 12),
        Expanded(
          flex: 115,
          child: Column(
            children: [
              if (trend != null) trend!,
              if (trend != null && subcategory != null)
                const SizedBox(height: 12),
              if (subcategory != null) subcategory!,
            ],
          ),
        ),
      ],
    );
  }
}

/// Selettore del periodo della Dashboard: alterna tra vista annuale e mese
/// specifico, con le frecce per scorrere anno/mese.
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.year,
    required this.month,
    required this.onModeChanged,
    required this.onPrev,
    required this.onNext,
  });

  final int year;
  final int? month;
  final ValueChanged<bool> onModeChanged; // true = mese, false = anno
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isMonth = month != null;
    final label =
        isMonth ? _capitalize(AppFormatters.monthYear(year, month!)) : '$year';

    return Column(
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Anno')),
            ButtonSegment(value: true, label: Text('Mese')),
          ],
          selected: {isMonth},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
              tooltip: isMonth ? 'Mese precedente' : 'Anno precedente',
            ),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              tooltip: isMonth ? 'Mese successivo' : 'Anno successivo',
            ),
          ],
        ),
      ],
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
