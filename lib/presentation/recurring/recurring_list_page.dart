import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/recurring_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../domain/entities/recurring_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../shared_widgets/fade_in_item.dart';

/// Lista dei movimenti ricorrenti (Milestone M5).
///
/// Ogni voce mostra descrizione, importo con segno, categoria, frequenza e
/// data della prossima occorrenza, con un interruttore per metterla in pausa.
/// Tap = modifica; scorri per eliminare. Il "+" crea una nuova ricorrenza.
class RecurringListPage extends ConsumerWidget {
  const RecurringListPage({super.key});

  static String _frequencyLabel(RecurringFrequencyType f) {
    switch (f) {
      case RecurringFrequencyType.weekly:
        return 'Settimanale';
      case RecurringFrequencyType.monthly:
        return 'Mensile';
      case RecurringFrequencyType.yearly:
        return 'Annuale';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurringAsync = ref.watch(allRecurringProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);

    // Lookup id → categoria per mostrare nome/icona nella lista.
    final categoriesById = <int, Category>{
      for (final c in categoriesAsync.asData?.value ?? const <Category>[])
        c.id: c,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Ricorrenze')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recurring/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuova'),
      ),
      body: recurringAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyState(onAdd: () => context.push('/recurring/new'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return _RecurringTile(
                item: item,
                category: categoriesById[item.categoryId],
                frequencyLabel: _frequencyLabel(item.frequency),
              );
            },
          );
        },
      ),
    );
  }
}

class _RecurringTile extends ConsumerWidget {
  const _RecurringTile({
    required this.item,
    required this.category,
    required this.frequencyLabel,
  });

  final RecurringEntity item;
  final Category? category;
  final String frequencyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIncome = item.type == TransactionType.income;
    final signedAmount = isIncome ? item.amount : -item.amount;
    final amountColor =
        isIncome ? Colors.green.shade700 : theme.colorScheme.onSurface;

    final categoryLabel = category == null
        ? ''
        : '${category!.icon.isNotEmpty ? '${category!.icon} ' : ''}${category!.name}';

    final subtitle = [
      if (categoryLabel.isNotEmpty) categoryLabel,
      frequencyLabel,
      if (item.totalOccurrences != null)
        'occorrenza ${item.occurrencesGenerated}/${item.totalOccurrences}'
      else
        'prossima: ${AppFormatters.shortDate(item.nextOccurrence)}',
    ].join(' · ');

    return FadeInItem(
      key: ValueKey(item.id),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          color: theme.colorScheme.errorContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
        ),
        confirmDismiss: (_) => _confirmDelete(context),
        onDismissed: (_) async {
          await ref.read(deleteRecurringProvider).call(item.id!);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Ricorrenza eliminata');
          }
        },
        child: Opacity(
          opacity: item.active ? 1 : 0.5,
          child: ListTile(
            onTap: () => context.push('/recurring/edit', extra: item),
            title: Text(
              item.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle:
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppFormatters.signedCurrency(signedAmount),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: amountColor, fontWeight: FontWeight.w600),
                ),
                // Interruttore: mette in pausa/riattiva (non elimina).
                Switch.adaptive(
                  value: item.active,
                  onChanged: (v) =>
                      ref.read(setRecurringActiveProvider).call(item.id!, v),
                ),
                // Cestino: elimina completamente la ricorrenza (come le spese).
                // Lo switch la disattiva soltanto; per rimuoverla serve questo.
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Elimina',
                  color: theme.colorScheme.outline,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final ok = await _confirmDelete(context);
                    if (!ok || item.id == null) return;
                    await ref.read(deleteRecurringProvider).call(item.id!);
                    if (context.mounted) {
                      showSuccessSnackBar(context, 'Ricorrenza eliminata');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la ricorrenza?'),
        content: Text(
          'La ricorrenza "${item.description}" non genererà più transazioni. '
          'Le transazioni già create restano invariate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_repeat_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Nessuna ricorrenza', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Aggiungi spese o entrate che si ripetono (abbonamenti, '
              'stipendio, affitto): verranno registrate automaticamente alla '
              'scadenza.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi ricorrenza'),
            ),
          ],
        ),
      ),
    );
  }
}
