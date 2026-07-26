import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Impostazioni: gestione categorie, regole merchant, import/export,
/// tema, stato sync Turso.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categorie e sottocategorie'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/categories'),
          ),
          ListTile(
            leading: const Icon(Icons.rule_outlined),
            title: const Text('Regole di classificazione scontrini'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/rules'),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Importa operazioni da CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/import'),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Esporta operazioni in CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/export'),
          ),
          const ListTile(
            leading: Icon(Icons.sync_outlined),
            title: Text('Sync multi-dispositivo (Turso)'),
            subtitle: Text('Milestone M7'),
          ),
        ],
      ),
    );
  }
}
