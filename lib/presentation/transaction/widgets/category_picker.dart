import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/category_providers.dart';
import '../../../data/local/database/daos/category_dao.dart';
import '../../../data/mappers/transaction_mapper.dart';
import '../../../domain/entities/transaction_entity.dart';

/// Sottocategoria scelta + categoria derivata automaticamente da essa.
class SubCategorySelection {
  const SubCategorySelection({
    required this.categoryId,
    required this.subCategoryId,
  });

  final int categoryId;
  final int subCategoryId;
}

/// Picker unico e obbligatorio per la sottocategoria: qui non si sceglie
/// prima la categoria e poi (facoltativamente) la sottocategoria. Si sceglie
/// direttamente la sottocategoria — più specifica e più veloce da
/// individuare per chi conosce già le proprie spese/entrate — e la categoria
/// viene derivata automaticamente da essa.
///
/// Mostra un campo tappabile che apre un bottom sheet con ricerca e
/// raggruppamento per categoria padre.
class SubCategoryPicker extends ConsumerWidget {
  const SubCategoryPicker({
    super.key,
    required this.type,
    required this.selection,
    required this.onChanged,
  });

  final TransactionType type;
  final SubCategorySelection? selection;
  final ValueChanged<SubCategorySelection> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(subCategoriesForTypeProvider(type.toDrift()));

    return itemsAsync.when(
      data: (items) {
        final current = selection == null
            ? null
            : items
                .where((i) => i.subCategory.id == selection!.subCategoryId)
                .firstOrNull;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: items.isEmpty ? null : () => _openPicker(context, items),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Sottocategoria',
              errorText: items.isEmpty
                  ? 'Nessuna sottocategoria configurata per questo tipo'
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current == null
                        ? 'Seleziona sottocategoria'
                        : '${current.subCategory.icon.isNotEmpty ? '${current.subCategory.icon} ' : ''}'
                            '${current.subCategory.name}  ·  ${current.category.name}',
                    style: current == null
                        ? TextStyle(color: Theme.of(context).hintColor)
                        : null,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Errore sottocategorie: $e'),
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    List<SubCategoryWithCategory> items,
  ) async {
    final selected = await showModalBottomSheet<SubCategoryWithCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SubCategorySheet(items: items),
    );
    if (selected != null) {
      onChanged(SubCategorySelection(
        categoryId: selected.category.id,
        subCategoryId: selected.subCategory.id,
      ));
    }
  }
}

class _SubCategorySheet extends StatefulWidget {
  const _SubCategorySheet({required this.items});

  final List<SubCategoryWithCategory> items;

  @override
  State<_SubCategorySheet> createState() => _SubCategorySheetState();
}

class _SubCategorySheetState extends State<_SubCategorySheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.subCategory.name.toLowerCase().contains(_query) ||
                i.category.name.toLowerCase().contains(_query))
            .toList();

    // L'ordine arriva già raggruppato per categoria/nome dal DAO (query
    // ordinata per categoria poi sottocategoria): qui raggruppiamo solo
    // visivamente, mantenendo l'ordine.
    final grouped = <String, List<SubCategoryWithCategory>>{};
    for (final item in filtered) {
      final header = item.category.icon.isNotEmpty
          ? '${item.category.icon} ${item.category.name}'
          : item.category.name;
      grouped.putIfAbsent(header, () => []).add(item);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Cerca sottocategoria...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.toLowerCase()),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Nessun risultato'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 4),
                            child: Text(
                              entry.key,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          for (final item in entry.value)
                            ListTile(
                              leading: item.subCategory.icon.isNotEmpty
                                  ? Text(item.subCategory.icon,
                                      style: const TextStyle(fontSize: 20))
                                  : const SizedBox(width: 24),
                              title: Text(item.subCategory.name),
                              onTap: () => Navigator.of(context).pop(item),
                            ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
