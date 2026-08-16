import 'package:flutter/material.dart';

/// Indicatore "non ancora impostato" nella griglia di mesi/categorie su
/// finestra larga (M29): solo l'icona, in alto a destra della card, stessa
/// posizione delle cifre spesa/totale sulle card già impostate — non un
/// pulsante proprio, la card è già toccabile nel suo insieme via l'InkWell
/// che la avvolge. Sostituisce il testo "Imposta →"/"Aggiungi" usato in
/// modalità lista (sotto la soglia): ingombrante e ridondante su una card
/// piccola, richiesto da Mario durante la revisione del mockup (16 ago 2026).
class AddIcon extends StatelessWidget {
  const AddIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.add, size: 15, color: colorScheme.onPrimaryContainer),
    );
  }
}
