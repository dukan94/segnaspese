import 'package:flutter/material.dart';

/// Distacco visivo tra sezioni di una pagina a lista lunga (Admin,
/// Impostazioni): più respiro di un semplice `SizedBox`, con una riga a
/// separare chiaramente dove finisce una sezione e inizia la successiva.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Divider(height: 1),
    );
  }
}
