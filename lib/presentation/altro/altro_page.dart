import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Hub "Altro": raccoglie le sezioni secondarie (Storico, Ricorrenze,
/// Impostazioni) per non affollare la barra di navigazione principale, che
/// resta a 4 voci (Home · Dashboard · Budget · Altro).
///
/// Ogni voce apre la relativa sezione a schermo intero (route top-level, con
/// pulsante Indietro).
class AltroPage extends StatelessWidget {
  const AltroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Altro')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _AltroTile(
            icon: Icons.receipt_long_outlined,
            title: 'Storico',
            subtitle: 'Tutte le operazioni, con ricerca',
            onTap: () => context.push('/history'),
          ),
          _AltroTile(
            icon: Icons.autorenew_outlined,
            title: 'Ricorrenze',
            subtitle: 'Spese ed entrate che si ripetono',
            onTap: () => context.push('/recurring'),
          ),
          _AltroTile(
            icon: Icons.settings_outlined,
            title: 'Impostazioni',
            subtitle: 'Categorie, regole di classificazione, import',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _AltroTile extends StatelessWidget {
  const _AltroTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
