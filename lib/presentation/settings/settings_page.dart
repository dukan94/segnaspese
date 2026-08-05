import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Impostazioni: gestione categorie, regole merchant, export, tema, stato
/// sync Turso. L'import CSV e il bridge Google Sheet vivono in "Admin"
/// (strumenti interni, v. admin_page.dart), fuori da questo flusso normale.
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
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Esporta operazioni in CSV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/export'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Importa estratto conto bancario'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/statement-import'),
          ),
          ListTile(
            leading: const Icon(Icons.sync_outlined),
            title: const Text('Sync multi-dispositivo (Turso)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/sync'),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI per scontrini (Gemini)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/gemini'),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Tema'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/theme'),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('Admin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/admin'),
          ),
        ],
      ),
    );
  }
}
