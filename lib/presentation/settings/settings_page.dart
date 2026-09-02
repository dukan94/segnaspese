import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared_widgets/content_width_limiter.dart';
import '../shared_widgets/section_divider.dart';

/// Impostazioni: gestione categorie, export, tema, integrazioni esterne
/// opzionali (Sync, raggruppata sotto "Configurazioni" — non obbligatoria
/// per usare l'app, M48). "Lettura scontrini" (Regole di classificazione +
/// Gemini) è disabilitata in blocco insieme allo scan in Home (bug noto,
/// M48). L'import CSV vive in "Admin" (strumenti interni, v. admin_page.dart),
/// fuori da questo flusso normale.
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
            // "Lettura scontrini" (M48, 2 set 2026): sezione intera
            // disabilitata insieme allo scan in Home — la lettura scontrino
            // non funziona bene al momento, non ha senso lasciar
            // configurare/modificare regole per una funzione che non si può
            // usare. A differenza di "Configurazioni" sotto, qui anche
            // l'intestazione è visivamente disabilitata (colore attenuato),
            // non solo le singole voci. Riabilitare insieme al bottone in
            // Home quando il problema sarà risolto.
            const _SectionHeader('Lettura scontrini', disabled: true),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.rule_outlined),
              title: Text('Regole di classificazione scontrini'),
              subtitle: Text('Temporaneamente non disponibile'),
            ),
            const ListTile(
              enabled: false,
              leading: Icon(Icons.smart_toy_outlined),
              title: Text('AI per scontrini (Gemini)'),
              subtitle: Text('Temporaneamente non disponibile'),
            ),
            const SectionDivider(),
            // "Configurazioni" (M48): integrazioni esterne opzionali che
            // richiedono una chiave/token proprio e hanno un fallback
            // quando mancano (sync disattivata -> banner in Home) — non
            // obbligatorie per usare l'app.
            const _SectionHeader('Configurazioni'),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
              title: const Text('Sync multi-dispositivo (Turso)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/sync'),
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
  const _SectionHeader(this.label, {this.disabled = false});

  final String label;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        label,
        style: disabled
            ? style?.copyWith(color: Theme.of(context).disabledColor)
            : style,
      ),
    );
  }
}
