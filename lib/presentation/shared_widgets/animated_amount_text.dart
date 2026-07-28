import 'package:flutter/material.dart';

/// Testo di un importo che anima un "conteggio" (dal valore precedente al
/// nuovo, non di scatto) quando [value] cambia — es. dopo aver salvato una
/// spesa, il saldo scorre invece di aggiornarsi bruscamente. [formatter] è
/// tipicamente `AppFormatters.currency` o `AppFormatters.signedCurrency`.
///
/// Si appoggia al comportamento nativo di [TweenAnimationBuilder]: quando il
/// [Tween] passato cambia `end` tra due build, l'animazione riparte dal
/// valore attualmente mostrato (non da `begin`, usato solo al primo build).
class AnimatedAmountText extends StatelessWidget {
  const AnimatedAmountText({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = const Duration(milliseconds: 500),
  });

  final double value;
  final String Function(double) formatter;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) =>
          Text(formatter(animatedValue), style: style),
    );
  }
}
