import 'package:flutter/material.dart';

import 'category_icon.dart';

/// Campo "Icona" dei form categoria/sottocategoria (M60): anteprima
/// dell'icona scelta nel colore della categoria; al tocco apre il selettore
/// a griglia ([showCategoryIconPicker]).
///
/// [value] è il valore della colonna `icon` (chiave M60, emoji precedente o
/// vuoto). Con [allowNone] (sottocategorie, icona opzionale) il selettore
/// offre anche "Usa l'icona della categoria" (valore vuoto), e l'anteprima
/// mostra [noneIcon] quando il valore è vuoto.
class CategoryIconField extends StatelessWidget {
  const CategoryIconField({
    super.key,
    required this.value,
    required this.color,
    required this.onChanged,
    this.allowNone = false,
    this.noneIcon = '',
  });

  final String value;
  final int color;
  final ValueChanged<String> onChanged;
  final bool allowNone;
  final String noneIcon;

  @override
  Widget build(BuildContext context) {
    final hasOwn = categoryIconKeyFor(value) != null;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final picked = await showCategoryIconPicker(
          context,
          selected: categoryIconKeyFor(value),
          color: color,
          allowNone: allowNone,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Icona'),
        child: Row(
          children: [
            CategoryIcon(
              icon: allowNone && !hasOwn ? noneIcon : value,
              color: color,
              radius: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                allowNone && !hasOwn
                    ? 'Come la categoria'
                    : (hasOwn ? 'Tocca per cambiare' : 'Scegli un\'icona'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Selettore icona a griglia, raggruppato per tema
/// ([categoryIconGroups]), con le icone nel colore della categoria.
/// Ritorna la chiave scelta, `''` per "Usa l'icona della categoria" (solo
/// con [allowNone]) o `null` se chiuso senza scegliere.
Future<String?> showCategoryIconPicker(
  BuildContext context, {
  required String? selected,
  required int color,
  bool allowNone = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final fg = categoryIconForeground(context, color);
      return AlertDialog(
        title: const Text('Scegli un\'icona'),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (allowNone)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.subdirectory_arrow_right,
                      color: theme.colorScheme.outline),
                  title: const Text('Usa l\'icona della categoria'),
                  selected: selected == null,
                  onTap: () => Navigator.of(context).pop(''),
                ),
              for (final group in categoryIconGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(group.label, style: theme.textTheme.labelLarge),
                ),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final key in group.keys)
                      _IconChoice(
                        icon: categoryIcons[key]!,
                        color: color,
                        foreground: fg,
                        selected: key == selected,
                        onTap: () => Navigator.of(context).pop(key),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
        ],
      );
    },
  );
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.color,
    required this.foreground,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final int color;
  final Color foreground;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Color(color).withValues(alpha: 0.15) : null,
          border: selected ? Border.all(color: foreground, width: 2) : null,
        ),
        child: Icon(icon, color: foreground, size: 22),
      ),
    );
  }
}
