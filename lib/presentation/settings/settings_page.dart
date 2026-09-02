import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared_widgets/content_width_limiter.dart';
import '../shared_widgets/section_divider.dart';

/// Impostazioni: gestione categorie, regole merchant, export, tema,
/// integrazioni esterne opzionali (Sync/Gemini, raggruppate sotto
/// "Configurazioni" — non obbligatorie per usare l'app, M48). L'import CSV
/// vive in "Admin" (strumenti interni, v. admin_page.dart), fuori da questo
/// flusso normale.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ContentWidthLimiter(
        child: ListView(
          children: [
            // Voci più usate (gestione della propria tassonomia + movimento
            // dati): restano il primo contatto visivo, senza un'intestazione
            // "Generale" ridondante sopra la prima cosa che si vede aprendo
            // la pagina.
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
            const SectionDivider(),
            // "Configurazioni" (M48): integrazioni esterne opzionali, ognuna
            // richiede una chiave/token proprio e ha un fallback quando
            // manca (sync disattivata -> banner in Home; Gemini mancante ->
            // OCR offline) — non obbligatorie per usare l'app.
            const _SectionHeader('Configurazioni'),
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
            const SectionDivider(),
            const _SectionHeader('Aspetto'),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Tema'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/theme'),
            ),
            const SectionDivider(),
            // Admin resta staccato in fondo, senza intestazione testuale
            // (a differenza dei gruppi sopra): "fuori dal flusso normale"
            // per design, ora anche protetto da PIN (M48).
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Admin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/admin'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
