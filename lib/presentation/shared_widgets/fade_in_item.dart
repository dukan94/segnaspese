import 'package:flutter/material.dart';

/// Fa apparire [child] con una dissolvenza + leggero scorrimento verso
/// l'alto quando entra per la prima volta nell'albero dei widget (es. una
/// nuova riga in una lista di Storico/Ricorrenze/Regole).
///
/// Va usato con una `key` stabile per elemento (tipicamente
/// `ValueKey(id)`), così l'animazione riparte solo per gli elementi
/// davvero nuovi — non per quelli già visibili che si ritrovano in una
/// posizione diversa dopo un aggiornamento della lista.
class FadeInItem extends StatefulWidget {
  const FadeInItem({super.key, required this.child});

  final Widget child;

  @override
  State<FadeInItem> createState() => _FadeInItemState();
}

class _FadeInItemState extends State<FadeInItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
      Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
          .animate(_fade);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
