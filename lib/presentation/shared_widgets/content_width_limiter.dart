import 'package:flutter/material.dart';

/// Centra [child] con una larghezza massima invece di stirarlo edge-to-edge
/// su una finestra larga: lo spazio in più resta respiro (margini), non
/// diventa contenuto aggiuntivo — richiesto esplicitamente da Mario durante
/// la discussione del refactor desktop (16 ago 2026, v. progettazione,
/// milestone M26/M27): "non cercare di riempire tutto".
class ContentWidthLimiter extends StatelessWidget {
  const ContentWidthLimiter({
    super.key,
    required this.child,
    this.maxWidth = 640,
  });

  final Widget child;

  /// Larghezza massima del contenuto. 640 (default) per pagine a colonna
  /// singola tipo form (Home); pagine con griglie/colonne interne (Dashboard,
  /// Budget) passano un valore maggiore.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
