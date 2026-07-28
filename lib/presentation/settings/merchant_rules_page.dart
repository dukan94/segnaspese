import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/category_providers.dart';
import '../../core/di/merchant_rule_providers.dart';
import '../../core/utils/app_snackbar.dart';
import '../../data/local/database/daos/category_dao.dart';
import '../../data/mappers/transaction_mapper.dart';
import '../../domain/entities/merchant_rule_entity.dart';
import '../../domain/entities/transaction_entity.dart';
import '../shared_widgets/fade_in_item.dart';
import '../transaction/widgets/category_picker.dart';

/// Schermata "Regole di classificazione scontrini" (Impostazioni, M3).
///
/// Ogni regola associa un pattern (regex applicata al testo dello scontrino)
/// a una categoria/sottocategoria. Le regole sono completamente modificabili;
/// quelle create dal flusso di apprendimento sono marcate come automatiche.
class MerchantRulesPage extends ConsumerWidget {
  const MerchantRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(merchantRulesProvider);
    // Per risolvere i nomi categoria/sottocategoria da mostrare.
    final subCatsAsync = ref
        .watch(subCategoriesForTypeProvider(TransactionType.expense.toDrift()));

    return Scaffold(
      appBar: AppBar(title: const Text('Regole di classificazione')),
      body: rulesAsync.when(
        data: (rules) {
          if (rules.isEmpty) {
            return const _EmptyState();
          }
          final lookup = subCatsAsync.valueOrNull ?? const [];
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: rules.length,
            itemBuilder: (context, index) => FadeInItem(
              key: ValueKey(rules[index].id),
              child: _RuleTile(rule: rules[index], lookup: lookup),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRuleEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Regola'),
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule, required this.lookup});

  final MerchantRuleEntity rule;
  final List<SubCategoryWithCategory> lookup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = _describeTarget(rule, lookup);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Tooltip(
          message:
              rule.isUserDefined ? 'Regola manuale' : 'Creata automaticamente',
          child: Icon(
            rule.isUserDefined
                ? Icons.person_outline
                : Icons.auto_awesome_outlined,
          ),
        ),
        title: Text(
          rule.pattern,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        subtitle: Text(
          '→ $target'
          '${rule.priority != 0 ? '  ·  priorità ${rule.priority}' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Modifica',
              onPressed: () => showRuleEditor(context, ref, existing: rule),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Elimina',
              onPressed: () => _confirmDelete(context, ref, rule),
            ),
          ],
        ),
      ),
    );
  }

  String _describeTarget(
    MerchantRuleEntity rule,
    List<SubCategoryWithCategory> lookup,
  ) {
    // Cerca prima per sottocategoria (più specifica).
    if (rule.subCategoryId != null) {
      final match = lookup
          .where((i) => i.subCategory.id == rule.subCategoryId)
          .firstOrNull;
      if (match != null) {
        return '${match.category.name} / ${match.subCategory.name}';
      }
    }
    final cat =
        lookup.where((i) => i.category.id == rule.categoryId).firstOrNull;
    return cat?.category.name ?? 'Categoria #${rule.categoryId}';
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  MerchantRuleEntity rule,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Eliminare la regola?'),
      content: Text('Pattern: ${rule.pattern}'),
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
  if (confirmed != true || !context.mounted) return;
  await ref.read(deleteMerchantRuleProvider).call(rule.id!);
  if (context.mounted) showSuccessSnackBar(context, 'Regola eliminata');
}

/// Apre il form di creazione/modifica di una regola.
Future<void> showRuleEditor(
  BuildContext context,
  WidgetRef ref, {
  MerchantRuleEntity? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RuleEditorDialog(existing: existing),
  );
}

class _RuleEditorDialog extends ConsumerStatefulWidget {
  const _RuleEditorDialog({this.existing});

  final MerchantRuleEntity? existing;

  @override
  ConsumerState<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<_RuleEditorDialog> {
  late final _patternController =
      TextEditingController(text: widget.existing?.pattern ?? '');
  late final _priorityController =
      TextEditingController(text: '${widget.existing?.priority ?? 0}');
  late SubCategorySelection? _selection = widget.existing == null
      ? null
      : SubCategorySelection(
          categoryId: widget.existing!.categoryId,
          subCategoryId: widget.existing!.subCategoryId ?? -1,
        );
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _patternController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pattern = _patternController.text.trim();
    if (pattern.isEmpty) {
      showErrorSnackBar(context, 'Inserisci un pattern');
      return;
    }
    if (_selection == null || _selection!.subCategoryId < 0) {
      showErrorSnackBar(context, 'Scegli una categoria/sottocategoria');
      return;
    }
    setState(() => _saving = true);

    final rule = MerchantRuleEntity(
      id: widget.existing?.id,
      pattern: pattern,
      categoryId: _selection!.categoryId,
      subCategoryId: _selection!.subCategoryId,
      priority: int.tryParse(_priorityController.text.trim()) ?? 0,
      isUserDefined: widget.existing?.isUserDefined ?? true,
    );

    try {
      if (_isEditing) {
        await ref.read(updateMerchantRuleProvider).call(rule);
      } else {
        await ref.read(addMerchantRuleProvider).call(rule);
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
      title: Text(_isEditing ? 'Modifica regola' : 'Nuova regola'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _patternController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Pattern (regex)',
                hintText: r'Es. ESSEL.*',
              ),
            ),
            const SizedBox(height: 16),
            SubCategoryPicker(
              type: TransactionType.expense,
              selection: (_selection != null && _selection!.subCategoryId >= 0)
                  ? _selection
                  : null,
              onChanged: (value) => setState(() => _selection = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priorityController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Priorità',
                helperText: 'Più alta = valutata prima',
              ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rule_outlined, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            'Nessuna regola. Aggiungine una o creale automaticamente '
            'confermando la categoria durante la scansione di uno scontrino.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
