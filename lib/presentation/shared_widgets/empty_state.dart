import 'package:flutter/material.dart';

/// Stato vuoto riutilizzabile: icona + messaggio, con [title] e [action]
/// opzionali per i casi a schermo intero (es. "Nessuna ricorrenza" con un
/// pulsante "Aggiungi"). Senza [title] resta compatto, adatto anche dentro
/// una card o un riquadro di ricerca.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.iconSize = 40,
    this.action,
    this.padding = const EdgeInsets.all(24),
  });

  final IconData icon;
  final String message;
  final String? title;
  final double iconSize;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTitle = title != null;
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: hasTitle
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            SizedBox(height: hasTitle ? 16 : 8),
            if (hasTitle) ...[
              Text(title!, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
