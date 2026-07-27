import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/settings_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_snackbar.dart';
import '../../../core/utils/formatters.dart';
import '../budget_providers.dart';
import 'budget_amount_dialog.dart';

/// Card "Riepilogo annuale" in cima al Budget: obiettivo di risparmio
/// (editabile), valori effettivi da inizio anno, previsione a fine anno e
/// quanto si può spendere al mese per centrare l'obiettivo. Sostituisce il
/// foglio Excel dell'utente.
class AnnualSummaryCard extends ConsumerWidget {
  const AnnualSummaryCard({
    super.key,
    required this.year,
    required this.includeExtra,
    required this.onIncludeExtraChanged,
  });

  final int year;
  final bool includeExtra;
  final ValueChanged<bool> onIncludeExtraChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecastAsync = ref
        .watch(annualForecastProvider((year: year, includeExtra: includeExtra)));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: forecastAsync.when(
          data: (f) => _content(context, ref, f),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Errore riepilogo: $e'),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, AnnualForecast f) {
    final theme = Theme.of(context);
    final green = Colors.green.shade600;
    final red = theme.colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Riepilogo annuale $year',
                  style: theme.textTheme.titleMedium),
            ),
            _GoalChip(goal: f.goal, onTap: () => _editGoal(context, ref, f.goal)),
          ],
        ),
        const Divider(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MiniTable(
                title: 'Effettive',
                subtitle: 'da inizio anno',
                income: f.incomeYtd,
                expense: f.expenseYtd,
                savings: f.savingsYtd,
                green: green,
                red: red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniTable(
                title: 'Previsione',
                subtitle: f.isProjected ? 'a fine anno' : 'anno concluso',
                income: f.incomeForecast,
                expense: f.expenseForecast,
                savings: f.savingsForecast,
                green: green,
                red: red,
              ),
            ),
          ],
        ),
        if (f.status != null) ...[
          const SizedBox(height: 12),
          _StatusBanner(status: f.status!, savingsForecast: f.savingsForecast),
        ],
        if (f.allowedMonthlySpend != null) ...[
          const Divider(height: 24),
          _Advice(
            allowedMonthlySpend: f.allowedMonthlySpend!,
            delta: f.delta!,
            green: green,
            red: red,
          ),
        ],
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: includeExtra,
          onChanged: onIncludeExtraChanged,
          title: const Text('Includi operazioni straordinarie'),
        ),
      ],
    );
  }

  Future<void> _editGoal(
      BuildContext context, WidgetRef ref, double? current) async {
    final controller = TextEditingController(
      text: current == null
          ? ''
          : current.toStringAsFixed(2).replaceAll('.', ','),
    );
    try {
      final value = await showDialog<double>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Obiettivo di risparmio annuo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(
              labelText: 'Importo',
              suffixText: '€',
              hintText: 'Es. 2.700,00',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = parseItalianAmount(controller.text);
                Navigator.of(context).pop(parsed);
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      );
      if (value == null) return;
      await ref.read(setAnnualSavingsGoalProvider)(value);
      if (context.mounted) showSuccessSnackBar(context, 'Obiettivo aggiornato');
    } finally {
      // Creato al di fuori di un widget State (metodo su ConsumerWidget):
      // senza smaltirlo qui, ogni apertura del dialog perdeva un controller.
      controller.dispose();
    }
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({required this.goal, required this.onTap});

  final double? goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.flag_outlined, size: 18),
      label: Text(goal == null
          ? 'Imposta obiettivo'
          : 'Obiettivo ${AppFormatters.currency(goal!)}'),
      onPressed: onTap,
    );
  }
}

class _MiniTable extends StatelessWidget {
  const _MiniTable({
    required this.title,
    required this.subtitle,
    required this.income,
    required this.expense,
    required this.savings,
    required this.green,
    required this.red,
  });

  final String title;
  final String subtitle;
  final double income;
  final double expense;
  final double savings;
  final Color green;
  final Color red;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        Text(subtitle, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _row(context, 'Reddito', income, green),
        _row(context, 'Spese', expense, red),
        _row(context, 'Risparmio', savings, savings >= 0 ? green : red,
            bold: true),
      ],
    );
  }

  Widget _row(BuildContext context, String label, double value, Color color,
      {bool bold = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          // Spazio minimo garantito: con "spaceBetween" e poco margine (due
          // colonne affiancate su schermo stretto) etichetta e importo
          // potevano finire quasi a contatto.
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                AppFormatters.currency(value),
                style: AppTheme.amountStyle(theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.savingsForecast});

  final ForecastStatus status;
  final double savingsForecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String text) = switch (status) {
      ForecastStatus.onTrack => (
          Icons.check_circle_outline,
          Colors.green.shade600,
          'In linea con l\'obiettivo'
        ),
      ForecastStatus.near => (
          Icons.trending_flat,
          Colors.orange.shade700,
          'Molto vicino all\'obiettivo'
        ),
      ForecastStatus.off => (
          Icons.error_outline,
          theme.colorScheme.error,
          'Risparmio previsto sotto l\'obiettivo'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _Advice extends StatelessWidget {
  const _Advice({
    required this.allowedMonthlySpend,
    required this.delta,
    required this.green,
    required this.red,
  });

  final double allowedMonthlySpend;
  final double delta;
  final Color green;
  final Color red;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deltaColor = delta >= 0 ? green : red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Per raggiungere l\'obiettivo', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Puoi spendere al mese'),
            Text(AppFormatters.currency(allowedMonthlySpend),
                style: AppTheme.amountStyle(theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700))),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(delta >= 0 ? 'Margine sulla spesa media' : 'Oltre la spesa media',
                style: theme.textTheme.bodySmall),
            Text(
              '${delta >= 0 ? '+' : ''}${AppFormatters.currency(delta)}',
              style: AppTheme.amountStyle(
                TextStyle(color: deltaColor, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
