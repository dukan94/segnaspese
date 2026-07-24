import 'package:flutter/material.dart';

/// SnackBar di conferma discreto, uniforme in tutta l'app: piccolo,
/// arrotondato, sfondo neutro e durata breve — segnala l'esito senza
/// interrompere il flusso dell'utente (a differenza dello SnackBar Material
/// di default, largo quanto lo schermo e con sfondo ad alto contrasto).
void showSuccessSnackBar(BuildContext context, String message) {
  final colorScheme = Theme.of(context).colorScheme;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(message, style: TextStyle(color: colorScheme.onSurface)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 1,
        duration: const Duration(seconds: 2),
        width: 280,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// Variante per messaggi di errore: stessa impronta grafica discreta, ma
/// colorata coerentemente con lo stato di errore del tema.
void showErrorSnackBar(BuildContext context, String message) {
  final colorScheme = Theme.of(context).colorScheme;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(message, style: TextStyle(color: colorScheme.onSurface)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.errorContainer,
        elevation: 1,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}
