import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  int? _selectedCategoryId;
  bool _includeExtraordinary = false;

  @override
  Widget build(BuildContext context) {
    final dataAsync = ref.watch(
      dashboardDataProvider((year: _year, includeExtra: _includeExtraordinary)),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _YearSelector(
          year: _year,
          onPrev: () => setState(() => _year--),
          onNext: () => setState(() => _year++),
        ),
        const SizedBox(height: 8),
        AnnualTotals(
          income: data.totalIncome,
          expense: data.totalExpense,
          budget: data.totalBudget,
          isOverBudget: data.isOverBudget,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: _includeExtraordinary,
          onChanged: (v) => setState(() => _includeExtraordinary = v),
          title: const Text('Includi operazioni straordinarie'),
          dense: true,
        ),
        const SizedBox(height: 8),
        _SectionCard(
          title: 'Spese per categoria',
          child: CategoryDonut(
            slices: data.byCategory,
            total: data.totalExpense,
            selectedCategoryId: selectedId,
            onSelect: (id) => setState(() => _selectedCategoryId = id),
          ),
        ),
        if (selectedSlice != null)
          _SectionCard(
            child: SubcategoryBars(
              categoryName: selectedSlice.name,
              color: selectedSlice.color,
              slices: data.subByCategory[selectedId] ?? const [],
            ),
          ),
        _SectionCard(
          title: 'Andamento 12 mesi',
          child: MonthlyTrendChart(
            monthlyExpense: data.monthlyExpense,
            monthlyBudget: data.monthlyBudget,
          ),
        ),
      ],
    );
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Anno precedente',
        ),
        Text('$year', style: Theme.of(context).textTheme.titleLarge),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Anno successivo',
        ),
      ],
    );
  }
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
