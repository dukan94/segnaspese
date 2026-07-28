import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/local/database/app_database.dart';
import '../../data/mappers/transaction_mapper.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../shared_widgets/empty_state.dart';

/// Palette di colori proposta per le categorie (usata nei grafici futuri
/// della Dashboard, M4). Solo un punto di partenza: l'utente sceglie tra
/// queste, niente color picker completo per restare semplice e veloce.
const _colorPalette = <int>[
  0xFF2E7D5B,
  0xFF4C8C63,
  0xFF6FA287,
  0xFF9BC1A8,
  0xFF1B5E3F,
  0xFFAD1457,
  0xFF546E7A,
  0xFFC62828,
  0xFF8D6E63,
  0xFFEF6C00,
  0xFF00838F,
  0xFF4527A0,
  0xFF6D4C41,
  0xFF1976D2,
  0xFF00695C,
  0xFF9E9D24,
];

/// Schermata "Categorie e sottocategorie" (Impostazioni), Milestone M2.
///
/// Due tab (Uscite/Entrate); ogni categoria è un `ExpansionTile` con le sue
/// sottocategorie annidate. Le modifiche sono immediate: le liste sono
/// reattive (Drift `watch()`), niente pull-to-refresh necessario.
class CategoriesManagePage extends StatelessWidget {
  const CategoriesManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categorie e sottocategorie'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Uscite'),
              Tab(text: 'Entrate'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CategoryTypeList(type: TransactionType.expense),
            _CategoryTypeList(type: TransactionType.income),
          ],
        ),
      ),
    );
  }
}

/// Lista categorie riordinabile via drag & drop (icona a 6 pallini). Tiene
/// una copia locale ottimistica dell'ordine: appena si rilascia il drag, la
/// UI riflette subito il nuovo ordine mentre il salvataggio (nella tabella
/// Settings, v. CategoryDao) avviene in background.
class _CategoryTypeList extends ConsumerStatefulWidget {
  const _CategoryTypeList({required this.type});

  final TransactionType type;

  @override
  ConsumerState<_CategoryTypeList> createState() => _CategoryTypeListState();
}

class _CategoryTypeListState extends ConsumerState<_CategoryTypeList> {
  List<Category> _items = [];

  /// Riprende l'elenco dal DB solo se è cambiato l'INSIEME delle categorie
  /// (es. una aggiunta o eliminata altrove). Se l'insieme è lo stesso e a
  /// differire è solo l'ordine, manteniamo l'ordine locale appena impostato
  /// dall'utente col drag & drop: lo stream delle categorie non riflette
  /// subito il riordino (è salvato nella tabella Settings, un'altra tabella),
  /// quindi risincronizzare qui farebbe "tornare al posto" gli elementi.
  void _syncItems(List<Category> incoming) {
    final incomingIds = incoming.map((c) => c.id).toSet();
    final sameSet = _items.length == incoming.length &&
        _items.every((c) => incomingIds.contains(c.id));
    if (!sameSet) {
      _items = List.of(incoming);
    } else {
      // Stesso insieme: preserva l'ordine locale ma aggiorna gli oggetti
      // (nome/icona/colore possono essere stati modificati).
      final byId = {for (final c in incoming) c.id: c};
      _items = [for (final c in _items) byId[c.id]!];
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    await ref
        .read(reorderCategoriesProvider)
        .call(widget.type, _items.map((c) => c.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync =
        ref.watch(categoriesByTypeProvider(widget.type.toDrift()));

    return Scaffold(
      body: categoriesAsync.when(
        data: (categories) {
          _syncItems(categories);
          if (_items.isEmpty) {
            return EmptyState(
              icon: Icons.category_outlined,
              title: 'Nessuna categoria',
              message:
                  'Aggiungine una per iniziare a classificare le operazioni.',
              action: FilledButton.icon(
                onPressed: () =>
                    showCategoryEditor(context, ref, type: widget.type),
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi categoria'),
              ),
            );
          }
          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: _items.length,
            onReorderItem: _onReorder,
            itemBuilder: (context, index) => _CategoryTile(
              key: ValueKey('category-${_items[index].id}'),
              category: _items[index],
              index: index,
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-category-${widget.type.name}',
        onPressed: () => showCategoryEditor(context, ref, type: widget.type),
        icon: const Icon(Icons.add),
        label: const Text('Categoria'),
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({super.key, required this.category, required this.index});

  final Category category;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Color(category.color).withValues(alpha: 0.2),
          child: Text(category.icon, style: const TextStyle(fontSize: 18)),
        ),
        title: Text(category.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Modifica categoria',
              onPressed: () =>
                  showCategoryEditor(context, ref, existing: category),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Elimina categoria',
              onPressed: () => _confirmDeleteCategory(context, ref, category),
            ),
          ],
        ),
        children: [
          _SubCategoryList(categoryId: category.id),
        ],
      ),
    );
  }
}

/// Lista sottocategorie di una categoria, anch'essa riordinabile via drag &
/// drop, annidata dentro l'`ExpansionTile` della categoria padre.
class _SubCategoryList extends ConsumerStatefulWidget {
  const _SubCategoryList({required this.categoryId});

  final int categoryId;

  @override
  ConsumerState<_SubCategoryList> createState() => _SubCategoryListState();
}

class _SubCategoryListState extends ConsumerState<_SubCategoryList> {
  List<SubCategory> _items = [];

  void _syncItems(List<SubCategory> incoming) {
    final incomingIds = incoming.map((s) => s.id).toSet();
    final sameSet = _items.length == incoming.length &&
        _items.every((s) => incomingIds.contains(s.id));
    if (!sameSet) {
      _items = List.of(incoming);
    } else {
      // Stesso insieme: preserva l'ordine locale (riordino ottimistico) e
      // aggiorna solo il contenuto degli elementi.
      final byId = {for (final s in incoming) s.id: s};
      _items = [for (final s in _items) byId[s.id]!];
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    await ref
        .read(reorderSubCategoriesProvider)
        .call(widget.categoryId, _items.map((s) => s.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final subCategoriesAsync =
        ref.watch(subCategoriesProvider(widget.categoryId));

    return subCategoriesAsync.when(
      data: (subCategories) {
        _syncItems(subCategories);
        return Column(
          children: [
            if (_items.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _items.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) {
                  final sub = _items[index];
                  return ListTile(
                    key: ValueKey('subcategory-${sub.id}'),
                    contentPadding: const EdgeInsets.only(left: 8, right: 8),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Row(
                      children: [
                        if (sub.icon.isNotEmpty) ...[
                          Text(sub.icon, style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: Text(sub.name)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Modifica sottocategoria',
                          onPressed: () => showSubCategoryEditor(
                            context,
                            ref,
                            categoryId: widget.categoryId,
                            existing: sub,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Elimina sottocategoria',
                          onPressed: () =>
                              _confirmDeleteSubCategory(context, ref, sub),
                        ),
                      ],
                    ),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showSubCategoryEditor(context, ref,
                      categoryId: widget.categoryId),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Aggiungi sottocategoria'),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Errore sottocategorie: $e'),
      ),
    );
  }
}

Future<void> _confirmDeleteCategory(
  BuildContext context,
  WidgetRef ref,
  Category category,
) async {
  final subCategories =
      await ref.read(subCategoriesProvider(category.id).future);
  if (!context.mounted) return;

  final confirmed = await _confirmDialog(
    context,
    title: 'Eliminare "${category.name}"?',
    message: subCategories.isEmpty
        ? 'Le operazioni già registrate con questa categoria non verranno modificate.'
        : 'Verranno eliminate anche le sue ${subCategories.length} sottocategorie. '
            'Le operazioni già registrate non verranno modificate.',
  );
  if (confirmed != true || !context.mounted) return;

  await ref.read(deleteCategoryProvider).call(category.id);
  if (context.mounted) {
    showSuccessSnackBar(context, 'Categoria eliminata');
  }
}

Future<void> _confirmDeleteSubCategory(
  BuildContext context,
  WidgetRef ref,
  SubCategory subCategory,
) async {
  final confirmed = await _confirmDialog(
    context,
    title: 'Eliminare "${subCategory.name}"?',
    message:
        'Le operazioni già registrate con questa sottocategoria non verranno modificate.',
  );
  if (confirmed != true || !context.mounted) return;

  await ref.read(deleteSubCategoryProvider).call(subCategory.id);
  if (context.mounted) {
    showSuccessSnackBar(context, 'Sottocategoria eliminata');
  }
}

Future<bool?> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Elimina'),
        ),
      ],
    ),
  );
}

/// Apre il form di creazione/modifica categoria. Passare [type] per creare
/// una nuova categoria di quel tipo, oppure [existing] per modificarne una
/// già esistente (il tipo non è modificabile dopo la creazione).
Future<void> showCategoryEditor(
  BuildContext context,
  WidgetRef ref, {
  TransactionType? type,
  Category? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CategoryEditorDialog(type: type, existing: existing),
  );
}

class _CategoryEditorDialog extends ConsumerStatefulWidget {
  const _CategoryEditorDialog({this.type, this.existing});

  final TransactionType? type;
  final Category? existing;

  @override
  ConsumerState<_CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<_CategoryEditorDialog> {
  late final _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _iconController =
      TextEditingController(text: widget.existing?.icon ?? '');
  late int _color = widget.existing?.color ?? _colorPalette.first;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final entity = CategoryEntity(
      id: widget.existing?.id,
      name: name,
      icon: _iconController.text.trim(),
      type: widget.existing?.type.toDomain() ?? widget.type!,
      color: _color,
      isDefault: widget.existing?.isDefault ?? false,
    );

    try {
      if (_isEditing) {
        await ref.read(updateCategoryProvider).call(entity);
      } else {
        await ref.read(addCategoryProvider).call(entity);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Modifica categoria' : 'Nuova categoria'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _iconController,
              decoration: const InputDecoration(
                labelText: 'Icona (emoji)',
                hintText: 'Es. 🏠',
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Colore'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in _colorPalette)
                  GestureDetector(
                    onTap: () => setState(() => _color = color),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(color),
                      child: _color == color
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 16)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salva'),
        ),
      ],
    );
  }
}

/// Apre il form di creazione/modifica sottocategoria per [categoryId].
Future<void> showSubCategoryEditor(
  BuildContext context,
  WidgetRef ref, {
  required int categoryId,
  SubCategory? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _SubCategoryEditorDialog(categoryId: categoryId, existing: existing),
  );
}

class _SubCategoryEditorDialog extends ConsumerStatefulWidget {
  const _SubCategoryEditorDialog({required this.categoryId, this.existing});

  final int categoryId;
  final SubCategory? existing;

  @override
  ConsumerState<_SubCategoryEditorDialog> createState() =>
      _SubCategoryEditorDialogState();
}

class _SubCategoryEditorDialogState
    extends ConsumerState<_SubCategoryEditorDialog> {
  late final _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _iconController =
      TextEditingController(text: widget.existing?.icon ?? '');
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final entity = SubCategoryEntity(
      id: widget.existing?.id,
      categoryId: widget.categoryId,
      name: name,
      icon: _iconController.text.trim(),
    );

    try {
      if (_isEditing) {
        await ref.read(updateSubCategoryProvider).call(entity);
      } else {
        await ref.read(addSubCategoryProvider).call(entity);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Errore: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(_isEditing ? 'Modifica sottocategoria' : 'Nuova sottocategoria'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _iconController,
            decoration: const InputDecoration(
              labelText: 'Icona (emoji, opzionale)',
              hintText: 'Es. 🛒',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salva'),
        ),
      ],
    );
  }
}
