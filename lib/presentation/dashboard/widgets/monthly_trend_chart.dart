import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Andamento degli ultimi 12 mesi: uscite (linea piena) con il budget
/// effettivo sovrapposto come linea tratteggiata. Asse X = mesi.
class MonthlyTrendChart extends StatelessWidget {
  const MonthlyTrendChart({
    super.key,
    required this.monthlyExpense,
    required this.monthlyBudget,
  });

  final List<double> monthlyExpense; // 12 valori (gen..dic)
  final List<double> monthlyBudget; // 12 valori

  static const _labels = ['G', 'F', 'M', 'A', 'M', 'G', 'L', 'A', 'S', 'O', 'N', 'D'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expenseColor = theme.colorScheme.error;
    final budgetColor = theme.colorScheme.primary;

    var maxValue = 0.0;
    for (final v in [...monthlyExpense, ...monthlyBudget]) {
      if (v > maxValue) maxValue = v;
    }
    final maxY = maxValue <= 0 ? 10.0 : maxValue * 1.15;
    final leftInterval = maxY / 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 11,
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < 12; i++)
                      FlSpot(i.toDouble(), monthlyExpense[i]),
                  ],
                  isCurved: false,
                  color: expenseColor,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < 12; i++)
                      FlSpot(i.toDouble(), monthlyBudget[i]),
                  ],
                  isCurved: false,
                  color: budgetColor,
                  barWidth: 2,
                  dashArray: const [6, 4],
                  dotData: const FlDotData(show: false),
                ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: leftInterval,
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i > 11) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_labels[i],
                            style: theme.textTheme.bodySmall),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: leftInterval,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0) return const SizedBox.shrink();
                      return Text(_compact(value),
                          style: theme.textTheme.bodySmall);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LegendDot(color: expenseColor, label: 'Uscite'),
            const SizedBox(width: 16),
            _LegendDot(color: budgetColor, label: 'Budget', dashed: true),
          ],
        ),
      ],
    );
  }

  static String _compact(double value) {
    if (value >= 1000) {
      final k = value / 1000;
      return '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            border: dashed ? Border.all(color: color, width: 1.5) : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
