import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/local/database/app_database.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../domain/services/money_rounding.dart';
import '../home/home_providers.dart';
import '../shared_widgets/content_width_limiter.dart';
import '../shared_widgets/empty_state.dart';
import '../shared_widgets/fade_in_item.dart';
import '../shared_widgets/transaction_list_item.dart';
import '../shared_widgets/transaction_row.dart';
import '../transaction/transaction_lookups.dart';

/// Storico: elenco completo delle operazioni con ricerca, modifica ed
/// eliminazione. Raggiungibile dalla barra di navigazione.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.initialQuery});

  /// Precompila la ricerca (es. doppio click su una categoria/sottocategoria
  /// in Dashboard, M34) — l'utente può comunque modificarla o cancellarla
  /// come una ricerca digitata a mano.
  final String? initialQuery;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  late final _searchController =
      TextEditingController(text: widget.initialQuery ?? '');
  late String _query = (widget.initialQuery ?? '').trim().toLowerCase();

  // Filtri separati dal testo (M45), combinati in AND con esso e tra loro.
  DateTimeRange? _dateRange;
  double? _minAmount;
  double? _maxAmount;

  bool get _hasDateFilter => _dateRange != null;
  bool get _hasAmountFilter => _minAmount != null || _maxAmount != null;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(allTransactionsProvider);
    // Categorie e sottocategorie per la ricerca per nome (M59: stessi
    // lookup usati dalla riga e dal dettaglio, non più ricostruiti qui).
    final lookups = ref.watch(transactionLookupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Storico')),
      body: ContentWidthLimiter(
        // Stessa larghezza di Home (760): lista a colonna singola, niente
        // master-detail (deciso con Mario per M30). Avvolge tutto il body
        // (ricerca + lista), non solo la lista: altrimenti la barra di
        // ricerca resterebbe stirata a piena larghezza sopra una lista
        // centrata sotto — incoerenza corretta insieme a M31.
        maxWidth: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Cerca per negozio, categoria, sottocategoria, importo, data...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                    ),
                  ),
                  // Filtri separati per data e importo (M45), a range,
                  // combinati in AND col testo. Icona colorata quando il
                  // filtro è attivo; tocca per impostare, tieni premuto per
                  // rimuovere (stesso principio del pulsante "x" del testo
                  // sopra, solo attivabile invece che sempre visibile).
                  _FilterIconButton(
                    icon: Icons.calendar_month_outlined,
                    active: _hasDateFilter,
                    tooltip: _hasDateFilter
                        ? 'Dal ${AppFormatters.shortDate(_dateRange!.start)} al ${AppFormatters.shortDate(_dateRange!.end)} — tieni premuto per rimuovere'
                        : 'Filtra per data',
                    onTap: _pickDateRange,
                    onLongPress: _hasDateFilter
                        ? () => setState(() => _dateRange = null)
                        : null,
                  ),
                  _FilterIconButton(
                    icon: Icons.euro,
                    active: _hasAmountFilter,
                    tooltip: _hasAmountFilter
                        ? 'Importo ${_minAmount != null ? 'da ${AppFormatters.currency(_minAmount!)} ' : ''}${_maxAmount != null ? 'a ${AppFormatters.currency(_maxAmount!)}' : ''} — tieni premuto per rimuovere'
                        : 'Filtra per importo',
                    onTap: _pickAmountRange,
                    onLongPress: _hasAmountFilter
                        ? () => setState(() {
                              _minAmount = null;
                              _maxAmount = null;
                            })
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: txAsync.when(
                data: (all) {
                  final filtered = _filter(
                    all,
                    lookups.categoriesById,
                    lookups.subCategoryNamesById,
                  );
                  if (filtered.isEmpty) {
                    final hasAnyFilter = _query.isNotEmpty ||
                        _hasDateFilter ||
                        _hasAmountFilter;
                    return EmptyState(
                      icon: all.isEmpty
                          ? Icons.receipt_long_outlined
                          : Icons.search_off_outlined,
                      message: all.isEmpty
                          ? 'Nessuna operazione'
                          : _query.isNotEmpty
                              ? 'Nessun risultato per "${_searchController.text}"'
                              : hasAnyFilter
                                  ? 'Nessun risultato con i filtri impostati'
                                  : 'Nessun risultato',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: filtered.length,
                    separatorBuilder: (context, i) => transactionRowDivider,
                    itemBuilder: (context, i) {
                      final tx = filtered[i];
                      return FadeInItem(
                        key: ValueKey(tx.id),
                        child: TransactionListItem(transaction: tx),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Errore: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TransactionEntity> _filter(
    List<TransactionEntity> all,
    Map<int, Category> catById,
    Map<int, String> subNameById,
  ) {
    Iterable<TransactionEntity> result = all;

    // Filtro data (M45): confronto solo su anno/mese/giorno, ignorando
    // l'orario — DateTimeRange.end da showDateRangePicker è mezzanotte del
    // giorno scelto, non fine giornata, quindi va normalizzato allo stesso
    // modo di start per includere quel giorno.
    final range = _dateRange;
    if (range != null) {
      final from = DateTime(range.start.year, range.start.month, range.start.day);
      final to = DateTime(range.end.year, range.end.month, range.end.day);
      result = result.where((t) {
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return !d.isBefore(from) && !d.isAfter(to);
      });
    }

    // Filtro importo (M45): sempre arrotondato ai centesimi, stessa
    // precauzione degli altri confronti su double nel progetto (M42).
    if (_minAmount != null || _maxAmount != null) {
      final min = _minAmount != null ? roundToCents(_minAmount!) : null;
      final max = _maxAmount != null ? roundToCents(_maxAmount!) : null;
      result = result.where((t) {
        final amount = roundToCents(t.amount);
        if (min != null && amount < min) return false;
        if (max != null && amount > max) return false;
        return true;
      });
    }

    if (_query.isNotEmpty) {
      result = result.where((t) {
        final cat = catById[t.categoryId]?.name ?? '';
        final subCat = t.subCategoryId != null
            ? (subNameById[t.subCategoryId] ?? '')
            : '';
        final haystack = [
          t.note ?? '',
          cat,
          subCat,
          AppFormatters.shortDate(t.date),
          t.amount.toStringAsFixed(2),
          t.amount.toStringAsFixed(2).replaceAll('.', ','),
        ].join(' ').toLowerCase();
        return haystack.contains(_query);
      });
    }

    return result.toList();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _pickAmountRange() async {
    final minController = TextEditingController(
      text: _minAmount != null ? _minAmount!.toStringAsFixed(2) : '',
    );
    final maxController = TextEditingController(
      text: _maxAmount != null ? _maxAmount!.toStringAsFixed(2) : '',
    );
    final result = await showDialog<(double?, double?)?>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void apply() {
              final minText = minController.text.trim().replaceAll(',', '.');
              final maxText = maxController.text.trim().replaceAll(',', '.');
              final min = minText.isEmpty ? null : double.tryParse(minText);
              final max = maxText.isEmpty ? null : double.tryParse(maxText);
              if ((minText.isNotEmpty && min == null) ||
                  (maxText.isNotEmpty && max == null)) {
                setDialogState(() => error = 'Importo non valido');
                return;
              }
              if (min != null && max != null && min > max) {
                setDialogState(
                    () => error = 'Il minimo non può superare il massimo');
                return;
              }
              Navigator.of(context).pop((min, max));
            }

            return AlertDialog(
              title: const Text('Filtra per importo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: minController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Importo minimo (€)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Importo massimo (€)'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                ],
              ),
              actions: [
                if (_hasAmountFilter)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop((null, null)),
                    child: const Text('Rimuovi filtro'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: apply,
                  child: const Text('Applica'),
                ),
              ],
            );
          },
        );
      },
    );
    minController.dispose();
    maxController.dispose();
    if (result != null && mounted) {
      setState(() {
        _minAmount = result.$1;
        _maxAmount = result.$2;
      });
    }
  }
}

/// Icona filtro accanto alla ricerca (M45): colorata quando il filtro è
/// attivo, tocca per impostare/modificare, tieni premuto per rimuovere.
class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 22,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
